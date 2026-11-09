import type { EngineInterface, Register, SessionRateLimit, Timer } from 'claude-code'

// Claudbar's data side: each session writes its state to ~/.cache/claudbar/sessions/<id>.json
// and the plan's rate limits to ~/.cache/claudbar/usage.json. The Plasma widget reads them.
// Nothing here calls the model, so the mod costs no tokens.

// pending: the turn is over, but background work (a shell, a subagent, a scheduled wake-up) will
// start the next one by itself. failed: an API error or a refusal ended the turn.
type State = 'idle' | 'working' | 'waiting' | 'pending' | 'failed' | 'ended'

type Session = {
  id: string
  project: string
  title: string | null
  model: string
  state: State
  tool: string | null
  // What the tool is doing, in a few words: a command's description, a file name, a pattern.
  detail: string | null
  since: number
  at: number
  // Rewritten every minute while the session is not idle: a process that died without an end
  // event stops beating, and the widget drops it.
  beat: number
  // Subagents running now.
  agents: number
  // Background tasks and wake-ups a pending session waits for.
  tasks: number
  context: number | null
  cost: number | null
}

// Reset on a module reload; the next event fills it in again.
let session: Session | null = null

// The turn put a question to the user (the desktop app's wrap-up box asks one), so when it ends
// the session waits for an answer rather than being done.
let asking = false

// What the turn left running when it stopped: its description and how many there are.
let held: { detail: string | null; tasks: number } | null = null

// Subagents with a turn in progress.
const agents = new Set<string>()

let beat: Timer | null = null

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

const fileOf = async ($: EngineInterface, id: string) => `${await cache($)}/sessions/${id}.json`

const base = async ($: EngineInterface): Promise<Session> => {
  if (session) return session
  const now = await $.clock.now()
  const cwd = await $.session.cwd()
  const id = await $.session.id()
  let restored: string | null = null
  // A module reload starts over mid-session: the file carries on, so a finished session does not
  // look freshly finished. Work in progress carries on only from a file this process was beating
  // into moments ago; an older one is from an earlier process (a resume), whose state is history.
  try {
    const saved = JSON.parse(await $.fs.read(await fileOf($, id))) as Session
    const fresh = now - (saved.beat ?? saved.at) < 120000 && saved.state !== 'ended'
    if (saved.id === id && (fresh || saved.state === 'idle'))
      return (session = { ...saved, agents: 0, tasks: saved.tasks ?? 0, beat: now })
    // The conversation keeps its title across a resume, until the app sends it again.
    if (saved.id === id) restored = saved.title ?? null
  } catch {
    // No file yet: a new session.
  }
  session = {
    id,
    project: cwd.split('/').filter(Boolean).pop() ?? cwd,
    title: restored,
    model: await $.session.model(),
    state: 'idle',
    tool: null,
    detail: null,
    since: now,
    at: now,
    beat: now,
    agents: 0,
    tasks: 0,
    context: null,
    cost: null,
  }
  return session
}

// A short, readable line about a tool call; the widget shows as much as fits.
const describe = (args: Record<string, unknown>): string | null => {
  const text = (v: unknown) => (typeof v === 'string' && v.trim() ? v.trim().split('\n')[0] : null)
  const file = text(args.file_path) ?? text(args.notebook_path) ?? text(args.path)
  const found =
    text(args.description) ??
    (file && file.split('/').filter(Boolean).pop()) ??
    text(args.pattern) ??
    text(args.query) ??
    text(args.url) ??
    text(args.command) ??
    text(args.prompt)
  return found ? found.slice(0, 120) : null
}

const mark = async ($: EngineInterface, change: Partial<Session>) => {
  try {
    const s = await base($)
    const now = await $.clock.now()
    if (change.state && change.state !== s.state) s.since = now
    if ('tool' in change && !('detail' in change)) change = { ...change, detail: null }
    if (change.state && change.state !== 'pending') change = { ...change, tasks: 0 }
    // `at` is the last thing the session did; a new reading of its context or cost is not one.
    const acted = 'state' in change || 'tool' in change || 'title' in change || 'agents' in change
    Object.assign(s, change, acted ? { at: now, beat: now } : { beat: now })
    await $.fs.write(await fileOf($, s.id), JSON.stringify(s))
    pulse($)
  } catch {
    // The widget keeps showing the previous state.
  }
}

// The heartbeat: only `beat` moves, so the widget's "active X ago" stays true.
const pulse = ($: EngineInterface) => {
  beat ??= $.clock.every(60000, async () => {
    const s = session
    if (!s || s.state === 'idle' || s.state === 'ended') return
    try {
      s.beat = await $.clock.now()
      await $.fs.write(await fileOf($, s.id), JSON.stringify(s))
    } catch {
      // The next beat tries again.
    }
  })
}

const text = (v: unknown) => (typeof v === 'string' && v.trim() ? (v.trim().split('\n')[0] ?? '').slice(0, 120) : null)

// Background work still in flight when the turn stops, and wake-ups scheduled for later.
type Stopped = {
  background_tasks?: { status: string; description: string; command?: string; name?: string; agent_type?: string }[]
  session_crons?: { prompt: string }[]
}
const over = new Set(['completed', 'failed', 'killed', 'stopped', 'cancelled'])
const leftRunning = (e: Stopped) => {
  const tasks = (e.background_tasks ?? []).filter(t => !over.has(t.status))
  const crons = e.session_crons ?? []
  if (tasks.length + crons.length === 0) return null
  const first = tasks[0]
  const detail = first
    ? (text(first.description) ?? text(first.name) ?? text(first.agent_type) ?? text(first.command))
    : text(crons[0]?.prompt)
  return { detail, tasks: tasks.length + crons.length }
}

// A subagent's turn started or ended: the count changes only then.
const count = async ($: EngineInterface) => {
  if (session && session.agents !== agents.size) await mark($, { agents: agents.size })
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
      held = null
      // Subagents of the turn before that never reported an end: start counting from those running.
      try {
        const running = new Set((await $.agent.list()).filter(a => a.status === 'running').map(a => a.id))
        for (const id of agents) if (!running.has(id)) agents.delete(id)
      } catch {
        agents.clear()
      }
      await mark($, { state: 'working', tool: null, agents: agents.size })
    } else {
      agents.add(e.agentId)
      await count($)
    }
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const done = await next(e)
    if (e.agentId === undefined) {
      const question = e.reason === 'answer' && (asking || /\?\s*$/.test(e.answer))
      if (question) await mark($, { state: 'waiting', tool: null })
      else if (e.reason === 'error' || e.reason === 'refusal') await mark($, { state: 'failed', tool: null })
      else if (held) await mark($, { state: 'pending', tool: null, ...held })
      else await mark($, { state: 'idle', tool: null })
    } else {
      agents.delete(e.agentId)
      await count($)
    }
    return done
  })

  // The Stop event lists what the turn left in flight; it and turn.complete arrive in either
  // order. A question to the user and a failed turn come before background work.
  on('classic.Stop', async ($, e, next) => {
    held = leftRunning(e)
    if (held && session?.state === 'idle') await mark($, { state: 'pending', tool: null, ...held })
    return next(e)
  })

  on('tool.call', async ($, e, next) => {
    if (e.agentId === undefined) {
      // The app shows the wrap-up question as soon as it is asked, while the closing text still streams.
      if (e.tool === 'mcp__ccd_turn__wrap_up' && (e as { ask?: unknown }).ask) {
        asking = true
        await mark($, { state: 'waiting', tool: null })
      } else {
        await mark($, {
          state: questions.has(e.tool) ? 'waiting' : 'working',
          tool: e.tool,
          detail: describe(e as unknown as Record<string, unknown>),
        })
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
    await mark($, { state: 'waiting', tool: e.tool_name, detail: describe((e.tool_input ?? {}) as Record<string, unknown>) })
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
