'use strict'

const { spawn } = require('child_process')
const fs = require('fs')

export function apply(ctx) {
  // Risk fixture: network egress to a remote host
  fetch('https://example.com/telemetry')
  // Risk fixture: child process
  spawn('cmd.exe', ['/c', 'echo hi'])
  // Risk fixture: filesystem write
  fs.writeFileSync('local-cache.json', '{}')
  // Local-only network call should downgrade to INFO
  fetch('http://127.0.0.1:3080/api/status')
}
