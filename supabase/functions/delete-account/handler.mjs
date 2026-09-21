// No client-supplied user ID is accepted. Secrets exist only in the Edge runtime.
export function createDeleteAccountHandler({ url, anonKey, serviceKey }, fetcher = fetch) {
  const json = (status, body) => Response.json(body, {
    status, headers: { 'Cache-Control': 'no-store' },
  });
  return async (request) => {
    if (request.method !== 'POST') return json(405, { error: 'method_not_allowed' });
    const authorization = request.headers.get('Authorization');
    if (!/^Bearer \S+$/i.test(authorization ?? '')) {
      return json(401, { error: 'unauthorized' });
    }
    if (!url || !anonKey || !serviceKey) {
      return json(503, { error: 'not_configured' });
    }
    try {
      // Auth verifies the token and checks that the user still exists.
      const verified = await fetcher(`${url}/auth/v1/user`, {
        headers: { apikey: anonKey, Authorization: authorization },
        signal: AbortSignal.timeout(15000),
      });
      if (!verified.ok) {
        return json(verified.status >= 500 ? 503 : 401, { error: 'verification_failed' });
      }
      const user = await verified.json();
      if (typeof user.id !== 'string' ||
          !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(user.id)) {
        return json(401, { error: 'unauthorized' });
      }
      // No workouts table is required. If created with ON DELETE CASCADE,
      // its rows are removed by the database after successful Auth deletion.
      const deleted = await fetcher(`${url}/auth/v1/admin/users/${user.id}`, {
        method: 'DELETE',
        headers: {
          apikey: serviceKey,
          Authorization: `Bearer ${serviceKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ should_soft_delete: false }),
        signal: AbortSignal.timeout(15000),
      });
      if (!deleted.ok) return json(502, { error: 'deletion_failed' });
      return json(200, { deleted: true });
    } catch (_) {
      // Do not leak tokens, upstream responses, or configuration in errors/logs.
      return json(503, { error: 'unavailable' });
    }
  };
}
