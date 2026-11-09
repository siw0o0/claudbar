import { expect, mock, test } from 'claude-code/testing'

type On = Parameters<typeof mock.clock>[0]

// The hooks below stand for the engine: files are kept in memory, and the test reads the
// session's state file as the widget would.
const ID = '00000000-0000-4000-8000-000000000000'
const FILE = `/home/test/.cache/claudbar/sessions/${ID}.json`

const engine = (on: On) => {
  const files = new Map<string, string>()
  mock.clock(on)
  on('env.get', () => ({ value: '/home/test' }))
  on('fs.write', (_, e) => (files.set(e.path, e.text), { value: undefined }))
  on('fs.read', (_, e) => {
    const text = files.get(e.path)
    if (text === undefined) throw new Error('missing')
    return { value: text }
  })
  on('session.id', () => ({ value: ID }))
  on('session.cwd', () => ({ value: '/work/project' }))
  on('session.model', () => ({ value: 'claude-test' }))
  on('session.usage', () => ({ value: { startedAt: 0, context: { percent: 5, window: 200000 }, rateLimits: [] } }))
  on('agent.list', () => ({ value: [] }))
  on('turn.start', (_, e) => ({ turnId: e.turnId }))
  on('turn.complete', (_, e) => ({ text: e.answer }))
  on('classic.Stop', () => ({}))
  return () => JSON.parse(files.get(FILE) ?? '{}')
}

test('a turn that leaves a background task waits for it', async ($, on) => {
  const state = engine(on)
  await $.turn.start({ text: 'run the tests', turnId: 't1' })
  expect(state().state).toBe('working')

  await $.turn.complete({ turnId: 't1', reason: 'answer', answer: 'Started the tests.', durationMs: 0, isAborted: false })
  expect(state().state).toBe('idle')
  await $.classic.Stop({
    stop_hook_active: false,
    background_tasks: [
      { id: 'b0', type: 'shell', status: 'completed', description: 'Lint', command: 'lint' },
      { id: 'b1', type: 'shell', status: 'running', description: 'Run the tests', command: 'make test' },
    ],
    session_crons: [],
  })
  expect(state()).toMatchObject({ state: 'pending', detail: 'Run the tests', tasks: 1 })

  // The task's notification starts the next turn.
  await $.turn.start({ text: '', turnId: 't2' })
  expect(state()).toMatchObject({ state: 'working', tasks: 0 })
})

test('the Stop event may come before the end of the turn', async ($, on) => {
  const state = engine(on)
  await $.turn.start({ text: 'wake me later', turnId: 't1' })
  await $.classic.Stop({ stop_hook_active: false, background_tasks: [], session_crons: [{ id: 'c1', schedule: '0 9 * * *', recurring: false, prompt: 'Check the deploy' }] })
  expect(state().state).toBe('working')
  await $.turn.complete({ turnId: 't1', reason: 'answer', answer: 'Scheduled.', durationMs: 0, isAborted: false })
  expect(state()).toMatchObject({ state: 'pending', detail: 'Check the deploy', tasks: 1 })
})

test('a question comes before background work, and nothing left means done', async ($, on) => {
  const state = engine(on)
  await $.turn.start({ text: 'go', turnId: 't1' })
  await $.turn.complete({ turnId: 't1', reason: 'answer', answer: 'Which one?', durationMs: 0, isAborted: false })
  await $.classic.Stop({ stop_hook_active: false, background_tasks: [{ id: 'b1', type: 'shell', status: 'running', description: 'Build' }], session_crons: [] })
  expect(state().state).toBe('waiting')

  await $.turn.start({ text: 'the first', turnId: 't2' })
  await $.turn.complete({ turnId: 't2', reason: 'answer', answer: 'Done.', durationMs: 0, isAborted: false })
  await $.classic.Stop({ stop_hook_active: false, background_tasks: [], session_crons: [] })
  expect(state().state).toBe('idle')
})

test('an API error shows as failed, and subagents are counted', async ($, on) => {
  const state = engine(on)
  await $.turn.start({ text: 'go', turnId: 't1' })
  await $.turn.start({ text: 'explore', turnId: 's1', agentId: 'a1' })
  expect(state().agents).toBe(1)
  await $.turn.complete({ turnId: 's1', agentId: 'a1', reason: 'answer', answer: 'found', durationMs: 0, isAborted: false })
  expect(state().agents).toBe(0)
  await $.turn.complete({ turnId: 't1', reason: 'error', answer: '', durationMs: 0, isAborted: false })
  expect(state().state).toBe('failed')
})
