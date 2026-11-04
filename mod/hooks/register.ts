import type { EngineInterface, Register, SessionRateLimit } from 'claude-code'

// Claudbar's data side: each session writes its state to ~/.cache/claudbar/sessions/<id>.json
// and the plan's rate limits to ~/.cache/claudbar/usage.json. The Plasma widget reads them.
// Nothing here calls the model, so the mod costs no tokens.

type State = 'idle' | 'working' | 'waiting' | 'ended'

type Session = {
  id: string
  project: string
  title: string | null
  model: string
  state: State
  tool: string | null
  since: number
  at: number
  context: number | null
  cost: number | null
}

// Reset on a module reload; the next event fills it in again.
let session: Session | null = null

// The turn put a question to the user (the desktop app's wrap-up box asks one), so when it ends
// the session waits for an answer rather than being done.
let asking = false

// Tools that stop the turn until the user answers.
const questions = new Set(['AskUserQuestion', 'ExitPlanMode'])

const cache = async ($: EngineInterface) => `${(await $.env.get('HOME')) ?? '/tmp'}/.cache/claudbar`

type Limit = { kind: string; percent: number; resetsAt: string | null }

// The last reading of each window: a response may report only some of them.
let known: Record<string, Limit> | null = null

const saveLimits = async ($: EngineInterface, limits: readonly SessionRateLimit[]) => {
  // No reading yet (outside a subscription, or before the first response): keep the last file.
  if (limits.length === 0) return

  const path = `${await cache($)}/usage.json`
  try {
    if (!known) {
      known = {}
      try {
        for (const l of (JSON.parse(await $.fs.read(path)) as { limits: Limit[] }).limits) known[l.kind] = l
      } catch {
        // No earlier file: start from this reading.
      }
    }
    for (const l of limits) known[l.kind] = { kind: l.kind, percent: l.percentUsed, resetsAt: l.resetsAt ?? null }
    // A window whose reset has passed starts over; drop it until a response reports it again.
    const now = await $.clock.now()
    const current = Object.values(known).filter(l => !l.resetsAt || Date.parse(l.resetsAt) > now)
    await $.fs.write(path, JSON.stringify({ at: now, limits: current }))
  } catch {
    // The widget keeps showing the last saved reading.
  }
}

const base = async ($: EngineInterface): Promise<Session> => {
  if (session) return session
  const now = await $.clock.now()
  const cwd = await $.session.cwd()
  session = {
    id: await $.session.id(),
    project: cwd.split('/').filter(Boolean).pop() ?? cwd,
    title: null,
    model: await $.session.model(),
    state: 'idle',
    tool: null,
    since: now,
    at: now,
    context: null,
    cost: null,
  }
  return session
}

const mark = async ($: EngineInterface, change: Partial<Session>) => {
  try {
    const s = await base($)
    const now = await $.clock.now()
    if (change.state && change.state !== s.state) s.since = now
    Object.assign(s, change, { at: now })
    await $.fs.write(`${await cache($)}/sessions/${s.id}.json`, JSON.stringify(s))
  } catch {
    // The widget keeps showing the previous state.
  }
}

const measure = async ($: EngineInterface) => {
  const usage = await $.session.usage()
  await mark($, { context: usage.context.percent ?? null, cost: usage.cost?.usd ?? null, model: await $.session.model() })
}

// After the permission decision the tool either ran or was refused: the session works again.
// A question at the end of a turn names no tool and waits past it.
const resume = async ($: EngineInterface) => {
  if (session?.state === 'waiting' && session.tool) await mark($, { state: 'working' })
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    await saveLimits($, (await $.session.usage()).rateLimits)
    // /clear or a resume changes the id; a title already set for this session stays.
    if (session && session.id !== (await $.session.id())) session = null
    await measure($)

    return started
  })

  on('session.measure', async ($, e, next) => {
    const measured = await next(e)
    if (e.changed.includes('rateLimits')) await saveLimits($, e.rateLimits)
    await measure($)

    return measured
  })

  // Only the main loop drives the state; subagents do not.
  on('turn.start', async ($, e, next) => {
    if (e.agentId === undefined) {
      asking = false
      await mark($, { state: 'working', tool: null })
    }
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const done = await next(e)
    if (e.agentId === undefined) {
      const question = e.reason === 'answer' && (asking || /\?\s*$/.test(e.answer))
      await mark($, { state: question ? 'waiting' : 'idle', tool: null })
    }
    return done
  })

  on('tool.call', async ($, e, next) => {
    if (e.agentId === undefined) {
      // The app shows the wrap-up question as soon as it is asked, while the closing text still streams.
      if (e.tool === 'mcp__ccd_turn__wrap_up' && (e as { ask?: unknown }).ask) {
        asking = true
        await mark($, { state: 'waiting', tool: null })
      } else {
        await mark($, { state: questions.has(e.tool) ? 'waiting' : 'working', tool: e.tool })
      }
    }
    return next(e)
  })

  // The conversation's title (its name in the sidebar) arrives with these two classic events.
  on('classic.SessionStart', async ($, e, next) => {
    if (e.session_title) await mark($, { title: e.session_title })
    return next(e)
  })

  on('classic.UserPromptSubmit', async ($, e, next) => {
    if (e.session_title && e.session_title !== session?.title) await mark($, { title: e.session_title })
    return next(e)
  })

  on('classic.PermissionRequest', async ($, e, next) => {
    await mark($, { state: 'waiting', tool: e.tool_name })
    return next(e)
  })

  on('classic.PostToolUse', async ($, e, next) => (await resume($), next(e)))
  on('classic.PostToolUseFailure', async ($, e, next) => (await resume($), next(e)))
  on('classic.PermissionDenied', async ($, e, next) => (await resume($), next(e)))

  on('session.end', async ($, e, next) => {
    await mark($, { state: 'ended', tool: null })
    return next(e)
  })
}
