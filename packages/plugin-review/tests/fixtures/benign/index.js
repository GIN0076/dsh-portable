'use strict'

export const name = 'fixture-benign'

export function apply(ctx) {
  console.log('hello from benign fixture plugin')
  ctx.on('session/created', () => {})
}
