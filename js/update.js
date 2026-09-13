/**
 * Update checker for a static deployment.
 *
 * The deploy workflow stamps the same build id into `index.html` (a meta tag)
 * and into `version.json`. The running page therefore knows what it was built
 * from, and can ask the server what is published now. When those differ a new
 * version has gone live while this tab was open, so we simply reload.
 *
 * Checks only run from the menu, never mid-match, and a guard makes sure we
 * never reload more than once for the same build.
 */
const RELOADED_KEY = 'slapshot-reloaded-for';
const MIN_INTERVAL_MS = 60_000;

let lastCheck = 0;
let checking = false;

function currentBuild() {
  const el = document.querySelector('meta[name="build"]');
  return el ? el.content : null;
}

function alreadyReloadedFor(version) {
  try { return sessionStorage.getItem(RELOADED_KEY) === version; } catch (e) { return false; }
}

function rememberReload(version) {
  try { sessionStorage.setItem(RELOADED_KEY, version); } catch (e) { /* private mode */ }
}

/**
 * Fetch the published build id and reload if it differs from ours.
 * Never throws and never blocks: any failure (offline, missing file, local
 * development) just leaves the game running.
 * @returns {Promise<boolean>} true when a reload was triggered
 */
export async function checkForUpdate({ force = false } = {}) {
  const mine = currentBuild();
  // no stamp (local development) means there is nothing meaningful to compare
  if (!mine || mine === 'dev') return false;
  if (checking) return false;
  const now = Date.now();
  if (!force && now - lastCheck < MIN_INTERVAL_MS) return false;
  checking = true;
  lastCheck = now;
  try {
    const res = await fetch(`version.json?t=${now}`, { cache: 'no-store' });
    if (!res.ok) return false;
    const { version } = await res.json();
    if (!version || version === mine) return false;
    // a different build is live: reload once for it
    if (alreadyReloadedFor(version)) return false;
    rememberReload(version);
    location.reload();
    return true;
  } catch (e) {
    return false;               // offline or blocked: keep playing
  } finally {
    checking = false;
  }
}
