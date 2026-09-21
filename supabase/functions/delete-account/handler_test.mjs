import test from 'node:test';
import assert from 'node:assert/strict';
import { createDeleteAccountHandler } from './handler.mjs';

const config = { url: 'https://example.test', anonKey: 'public-test', serviceKey: 'secret-test' };
const userId = '11111111-1111-4111-8111-111111111111';
const request = (body = {}) => new Request('https://example.test/delete-account', {
  method: 'POST', headers: { Authorization: 'Bearer user-token' }, body: JSON.stringify(body),
});

test('rejects missing credentials and non-POST without any upstream call', async () => {
  const handler = createDeleteAccountHandler(config, () => assert.fail('unexpected fetch'));
  assert.equal((await handler(new Request('https://example.test', { method: 'POST' }))).status, 401);
  assert.equal((await handler(new Request('https://example.test'))).status, 405);
});

test('rejects invalid users, upstream outages, and missing configuration', async () => {
  for (const response of [Response.json({}, { status: 401 }), Response.json({ id: '../other' }),
    Response.json({}, { status: 503 })]) {
    let calls = 0;
    const handler = createDeleteAccountHandler(config, async () => { calls++; return response; });
    assert.notEqual((await handler(request())).status, 200);
    assert.equal(calls, 1);
  }
  assert.equal((await createDeleteAccountHandler({}, () => assert.fail())(request())).status, 503);
});

test('deletes only verified user, ignoring forged target and Premium claims', async () => {
  const calls = [];
  const handler = createDeleteAccountHandler(config, async (url, options) => {
    calls.push({ url, options });
    return Response.json(calls.length === 1 ? { id: userId } : {});
  });
  const response = await handler(request({ user_id: 'someone-else', premium: false }));
  assert.deepEqual(await response.json(), { deleted: true });
  assert.equal(calls.length, 2);
  assert.equal(calls[0].options.headers.Authorization, 'Bearer user-token');
  assert.equal(calls[1].url, `${config.url}/auth/v1/admin/users/${userId}`);
  assert.equal(calls[1].options.headers.Authorization, 'Bearer secret-test');
  assert.equal(calls[1].options.method, 'DELETE');
  assert.deepEqual(JSON.parse(calls[1].options.body), { should_soft_delete: false });
});

test('deletion failures and transport failures never return success or secrets', async () => {
  for (const failsWithException of [false, true]) {
    let calls = 0;
    const handler = createDeleteAccountHandler(config, async () => {
      if (++calls === 1) return Response.json({ id: userId });
      if (failsWithException) throw Error('secret-test');
      return Response.json({ error: 'secret-test' }, { status: 500 });
    });
    const response = await handler(request());
    assert.notEqual(response.status, 200);
    assert.ok(!(await response.text()).includes('secret-test'));
  }
});
