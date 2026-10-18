// Writes a match as a self-contained HTML replay (spec §7, SMASH-72).
//
// The metrics say whether a policy is improving. They cannot say whether it looks like hockey, and
// that is the thing being bought — the owner judges feel by eye, and until the policy is in an app
// on his phone there is nothing to look at. This is the cheap stand-in.
//
// **Two pitches, one scrubber, the same seed.** The learned team on the left, §7's written rules on
// the right, from identical kick-offs. A single replay only answers "is this hockey?", which is
// hard to judge cold; side by side against the thing we already have, the question becomes "which
// of these two looks more like a team", which anyone can answer in ten seconds.
//
// It is a **diagnostic, not a renderer**. Nothing here models how the game looks (ADR 0005 and
// 0006 own that); it is the smallest thing that shows how the dots behave.
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

    struct Tape {
        let frames: [Frame]
        let roles: [String]
        let teams: [Int]
        let score: [Int]
        let label: String
    }

    /// Plays one match and keeps every `stride` ticks.
    static func record(_ nets: [PolicyNet?], setup: MatchSetup, label: String, stride: Int = 6) -> Tape {
        var m = Match(setup)
        m.installPolicies(nets)
        var frames: [Frame] = []
        var n = 0
        let maxTicks = Int(setup.periodSeconds * 120.0 * 9.0)
        while m.result == nil && m.ticks < maxTicks {
            m.tick()
            n += 1
            guard n % stride == 0 else { continue }
            let s = m.snapshot
            frames.append(Frame(x: s.players.map(\.x), z: s.players.map(\.z),
                                bx: s.ball.x, bz: s.ball.z,
                                carrier: s.ball.carrier ?? -1, score: s.score))
        }
        let s = m.snapshot
        return Tape(frames: frames, roles: s.players.map { "\($0.role)" },
                    teams: s.players.map(\.team), score: s.score, label: label)
    }

    private static func json(_ t: Tape) -> String {
        func arr(_ xs: [Double]) -> String { "[" + xs.map { String(format: "%.2f", $0) }.joined(separator: ",") + "]" }
        let frames = t.frames.map { f in
            "{x:\(arr(f.x)),z:\(arr(f.z)),b:[\(String(format: "%.2f", f.bx)),\(String(format: "%.2f", f.bz))],c:\(f.carrier),s:[\(f.score[0]),\(f.score[1])]}"
        }.joined(separator: ",")
        return "{label:\"\(t.label)\",score:[\(t.score[0]),\(t.score[1])],teams:\(t.teams.description),"
            + "roles:\(t.roles.map { "\"\($0)\"" }.description),frames:[\(frames)]}"
    }

    /// One page: every tape as its own pitch, sharing a scrubber and a play button.
    static func html(title: String, tapes: [Tape], halfWidth: Double, halfLength: Double) -> String {
        let longest = tapes.map(\.frames.count).max() ?? 0
        return """
        <!doctype html><meta charset="utf-8"><title>\(title)</title>
        <style>
          :root { color-scheme: dark; }
          body { margin:0; background:#11151c; color:#dbe3ef;
                 font:14px ui-sans-serif,system-ui,-apple-system,sans-serif;
                 display:flex; flex-direction:column; align-items:center; gap:14px; padding:18px 16px; }
          h1 { font-size:15px; font-weight:600; margin:0; letter-spacing:.01em; text-align:center; }
          .pitches { display:flex; gap:18px; flex-wrap:wrap; justify-content:center; }
          .pitch { display:flex; flex-direction:column; align-items:center; gap:7px; }
          .cap { font-size:12px; color:#8b97ab; text-align:center; }
          .cap b { color:#dbe3ef; font-weight:600; }
          svg { background:#1b2a1f; border-radius:10px; width:min(330px,42vw); height:auto; }
          .bar { display:flex; align-items:center; gap:12px; width:min(700px,100%); }
          input[type=range] { flex:1; accent-color:#5aa9ff; }
          button { background:#2a3444; color:#dbe3ef; border:1px solid #3a4658;
                   border-radius:7px; padding:6px 15px; font:inherit; cursor:pointer; }
          button:hover { background:#344057; }
          .legend { font-size:11.5px; color:#8b97ab; text-align:center; max-width:640px; line-height:1.5; }
          @media (max-width:720px) { svg { width:min(330px,86vw); } }
        </style>
        <h1>\(title)</h1>
        <div class="pitches" id="pitches"></div>
        <div class="bar">
          <button id="go">play</button>
          <input id="s" type="range" min="0" max="\(max(longest - 1, 0))" value="0">
        </div>
        <div class="legend" id="t"></div>
        <div class="legend">
          Blue is team 0, orange team 1. The yellow dot is the ball; the ring marks whoever carries it.
          Faint circles are goalies. Every pitch starts from the same seeded kick-off, so any difference
          is the policy, not the draw. <b>Watch the middle pitch for shape:</b> with the same policy on
          both sides there is no §7 to exploit, so what you see is what it believes a team should look
          like.
        </div>
        <script>
        const TAPES = [\(tapes.map(json).joined(separator: ","))];
        const NS = 'http://www.w3.org/2000/svg';
        const HW = \(halfWidth), HL = \(halfLength);
        const host = document.getElementById('pitches');
        const views = TAPES.map(tape => {
          const wrap = document.createElement('div'); wrap.className = 'pitch';
          const cap = document.createElement('div'); cap.className = 'cap';
          cap.innerHTML = '<b>' + tape.label + '</b>';
          const svg = document.createElementNS(NS,'svg');
          svg.setAttribute('viewBox', (-HW-1)+' '+(-HL-1)+' '+(2*HW+2)+' '+(2*HL+2));
          svg.innerHTML =
            '<rect x="'+(-HW)+'" y="'+(-HL)+'" width="'+(2*HW)+'" height="'+(2*HL)+'" fill="none" stroke="#3d5c45" stroke-width=".25"/>'
            + '<line x1="'+(-HW)+'" y1="0" x2="'+HW+'" y2="0" stroke="#3d5c45" stroke-width=".2"/>'
            + '<circle cx="0" cy="0" r="4" fill="none" stroke="#3d5c45" stroke-width=".2"/>'
            + '<line x1="-3" y1="'+(-HL+4)+'" x2="3" y2="'+(-HL+4)+'" stroke="#54788f" stroke-width=".3"/>'
            + '<line x1="-3" y1="'+(HL-4)+'" x2="3" y2="'+(HL-4)+'" stroke="#54788f" stroke-width=".3"/>';
          const g = document.createElementNS(NS,'g'); svg.appendChild(g);
          const dots = tape.teams.map((t,i) => {
            const c = document.createElementNS(NS,'circle');
            const goalie = tape.roles[i] === 'goalie';
            c.setAttribute('r', goalie ? .95 : .8);
            c.setAttribute('fill', t===0 ? '#5aa9ff' : '#ff8a5a');
            c.setAttribute('opacity', goalie ? .5 : 1);
            g.appendChild(c); return c;
          });
          const ball = document.createElementNS(NS,'circle');
          ball.setAttribute('r','.45'); ball.setAttribute('fill','#ffe66a'); g.appendChild(ball);
          const ring = document.createElementNS(NS,'circle');
          ring.setAttribute('r','1.5'); ring.setAttribute('fill','none');
          ring.setAttribute('stroke','#ffe66a'); ring.setAttribute('stroke-width','.18'); g.appendChild(ring);
          wrap.appendChild(cap); wrap.appendChild(svg); host.appendChild(wrap);
          return {tape, dots, ball, ring, cap};
        });
        const sl = document.getElementById('s'), tt = document.getElementById('t'), go = document.getElementById('go');
        function draw(k){
          let text = [];
          for (const v of views) {
            const f = v.tape.frames[Math.min(k, v.tape.frames.length - 1)];
            if (!f) continue;
            for (let i=0;i<v.dots.length;i++){ v.dots[i].setAttribute('cx',f.x[i]); v.dots[i].setAttribute('cy',f.z[i]); }
            v.ball.setAttribute('cx',f.b[0]); v.ball.setAttribute('cy',f.b[1]);
            if (f.c>=0){ v.ring.setAttribute('cx',f.x[f.c]); v.ring.setAttribute('cy',f.z[f.c]); v.ring.setAttribute('opacity','1'); }
            else v.ring.setAttribute('opacity','0');
            v.cap.innerHTML = '<b>' + v.tape.label + '</b><br>' + f.s[0] + '–' + f.s[1];
            text.push(v.tape.label + ' ' + f.s[0] + '–' + f.s[1]);
          }
          tt.textContent = 'frame ' + k + ' / ' + \(max(longest - 1, 0)) + ' · ' + text.join('  ·  ');
        }
        sl.addEventListener('input', e => draw(+e.target.value));
        let timer = null;
        go.addEventListener('click', () => {
          if (timer){ clearInterval(timer); timer=null; go.textContent='play'; return; }
          go.textContent='pause';
          timer = setInterval(() => { const k = (+sl.value + 1) % \(max(longest, 1)); sl.value = k; draw(k); }, 33);
        });
        draw(0);
        </script>
        """
    }
}
