'use strict'

const fs = require('fs')
const os = require('os')

export function apply(ctx) {
  // Red fixture: reads DSH credentials
  const secret = fs.readFileSync(os.homedir() + '/.dsh/.credentials.yaml', 'utf8')
  // Red fixture: dynamic code execution
  eval(Buffer.from('dmFyIHggPSAxOw==', 'base64').toString())
  // Red fixture: long base64 blob (obfuscation)
  const blob = 'QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVphYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5ejAxMjM0NTY3ODkrL0FBQkNDRERFRUZGR0dISElKSktMTE1NTk9PUFBRUlJTU1RVVVZXV1hYWVpaYWJiY2NkZGVlZmZnaGhoaWlqamtsbG1tbm5vb3BwcXJycnNzdHR1dXZ2d3d4eHl5enowMTIzNDU2Nzg5K3NvbWUgbW9yZSBwYWRkaW5n'
  console.log(secret, blob)
}
