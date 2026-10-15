// Writes one match as a self-contained HTML replay (spec §7, SMASH-72).
//
// The metrics say whether a policy is improving. They cannot say whether it looks like hockey, and
// that is the thing being bought — the owner judges feel by eye, and until the policy is in an app
// on his phone there is nothing to look at. This is the cheap stand-in: a top-down SVG of one
// seeded match, scrubable, openable in a browser.
//
// It is a **diagnostic, not a renderer**. Nothing here is a model of how the game looks (ADR 0005,
// ADR 0006 own that); it is the smallest thing that answers "do the blue dots behave like a team".
import Foundation
import SmashCore

enum Replay {

    struct Frame {
        let x: [Double]
        let z: [Double]
        let bx: Double
        let bz: Double
        let carrier: Int
        let score: [Int]
    }

    /// Plays one match and returns every `stride` ticks as a frame.
    static func record(_ net: PolicyNet?, policyTeams: [Int], setup: MatchSetup,
                       stride: Int = 6) -> (frames: [Frame], roles: [String], teams: [Int], score: [Int]) {
        var m = Match(setup)
        if let net { m.installPolicy(net, teams: policyTeams) }
        var frames: [Frame] = []
        var n = 0
        while m.result == nil && m.ticks < 200_000 {
            m.tick()
            n += 1
            guard n % stride == 0 else { continue }
            let s = m.snapshot
            frames.append(Frame(x: s.players.map(\.x), z: s.players.map(\.z),
                                bx: s.ball.x, bz: s.ball.z,
                                carrier: s.ball.carrier ?? -1, score: s.score))
        }
        let s = m.snapshot
        return (frames, s.players.map { "\($0.role)" }, s.players.map(\.team), s.score)
    }

    /// A single HTML file: the pitch, the players, a scrubber and a play button.
    static func html(title: String, frames: [Frame], roles: [String], teams: [Int],
                     score: [Int], halfWidth: Double, halfLength: Double) -> String {
        func arr(_ xs: [Double]) -> String { "[" + xs.map { String(format: "%.2f", $0) }.joined(separator: ",") + "]" }
        let data = frames.map { f in
            "{x:\(arr(f.x)),z:\(arr(f.z)),b:[\(String(format: "%.2f", f.bx)),\(String(format: "%.2f", f.bz))],c:\(f.carrier),s:[\(f.score[0]),\(f.score[1])]}"
        }.joined(separator: ",\n")

        return """
        <!doctype html><meta charset="utf-8"><title>\(title)</title>
        <style>
          :root { color-scheme: dark; }
          body { margin:0; background:#11151c; color:#dbe3ef;
                 font:14px ui-sans-serif,system-ui,-apple-system,sans-serif;
                 display:flex; flex-direction:column; align-items:center; gap:12px; padding:16px; }
          h1 { font-size:15px; font-weight:600; margin:0; letter-spacing:.01em; }
          .meta { color:#8b97ab; font-size:12px; }
          svg { background:#1b2a1f; border-radius:10px; max-width:100%; height:auto; }
          .bar { display:flex; align-items:center; gap:10px; width:min(680px,100%); }
          input[type=range] { flex:1; accent-color:#5aa9ff; }
          button { background:#2a3444; color:#dbe3ef; border:1px solid #3a4658;
                   border-radius:7px; padding:5px 13px; font:inherit; cursor:pointer; }
          button:hover { background:#344057; }
        </style>
        <h1>\(title)</h1>
        <div class="meta">final \(score[0])–\(score[1]) · <span id="t"></span></div>
        <svg id="p" viewBox="\(-halfWidth - 1) \(-halfLength - 1) \(2 * halfWidth + 2) \(2 * halfLength + 2)" width="420">
          <rect x="\(-halfWidth)" y="\(-halfLength)" width="\(2 * halfWidth)" height="\(2 * halfLength)"
                fill="none" stroke="#3d5c45" stroke-width=".25"/>
          <line x1="\(-halfWidth)" y1="0" x2="\(halfWidth)" y2="0" stroke="#3d5c45" stroke-width=".2"/>
          <circle cx="0" cy="0" r="4" fill="none" stroke="#3d5c45" stroke-width=".2"/>
          <line x1="-3" y1="\(-halfLength + 4)" x2="3" y2="\(-halfLength + 4)" stroke="#54788f" stroke-width=".3"/>
          <line x1="-3" y1="\(halfLength - 4)" x2="3" y2="\(halfLength - 4)" stroke="#54788f" stroke-width=".3"/>
          <g id="g"></g>
        </svg>
        <div class="bar">
          <button id="go">play</button>
          <input id="s" type="range" min="0" max="\(max(frames.count - 1, 0))" value="0">
        </div>
        <script>
        const F = [\(data)];
        const TEAM = \(teams.description), ROLE = \(roles.map { "\"\($0)\"" }.description);
        const g = document.getElementById('g'), sl = document.getElementById('s');
        const tt = document.getElementById('t'), go = document.getElementById('go');
        const NS = 'http://www.w3.org/2000/svg';
        const dots = TEAM.map((t,i) => {
          const c = document.createElementNS(NS,'circle');
          c.setAttribute('r', ROLE[i]==='goalie' ? .95 : .8);
          c.setAttribute('fill', t===0 ? '#5aa9ff' : '#ff8a5a');
          c.setAttribute('opacity', ROLE[i]==='goalie' ? .65 : 1);
          g.appendChild(c); return c;
        });
        const ball = document.createElementNS(NS,'circle');
        ball.setAttribute('r','.45'); ball.setAttribute('fill','#ffe66a'); g.appendChild(ball);
        const ring = document.createElementNS(NS,'circle');
        ring.setAttribute('r','1.5'); ring.setAttribute('fill','none');
        ring.setAttribute('stroke','#ffe66a'); ring.setAttribute('stroke-width','.18'); g.appendChild(ring);
        function draw(k){
          const f = F[k]; if(!f) return;
          for(let i=0;i<dots.length;i++){ dots[i].setAttribute('cx',f.x[i]); dots[i].setAttribute('cy',f.z[i]); }
          ball.setAttribute('cx',f.b[0]); ball.setAttribute('cy',f.b[1]);
          if(f.c>=0){ ring.setAttribute('cx',f.x[f.c]); ring.setAttribute('cy',f.z[f.c]); ring.setAttribute('opacity','1'); }
          else ring.setAttribute('opacity','0');
          tt.textContent = 'frame '+k+'/'+(F.length-1)+' · '+f.s[0]+'–'+f.s[1];
        }
        sl.addEventListener('input', e => draw(+e.target.value));
        let timer = null;
        go.addEventListener('click', () => {
          if(timer){ clearInterval(timer); timer=null; go.textContent='play'; return; }
          go.textContent='pause';
          timer = setInterval(() => {
            let k = (+sl.value + 1) % F.length;
            sl.value = k; draw(k);
          }, 33);
        });
        draw(0);
        </script>
        """
    }
}
