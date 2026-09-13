// Language is picked from the browser locale: German for de-*, English otherwise.
const nav = (typeof navigator !== 'undefined' && navigator.language) || 'en';
export const LANG = nav.toLowerCase().startsWith('de') ? 'de' : 'en';

const S = {
  en: {
    // menu
    'menu.training': 'Training', 'menu.continue': 'Continue season', 'menu.newSeason': 'Start season', 'menu.newSeason2': 'Start a new season',
    'menu.quick': 'Quick match', 'menu.coach': 'Coach & settings', 'menu.help': 'How to play', 'menu.tagline': 'One finger. Six players. One goal.',
    'menu.trophies': '🏆 League titles: {league} · 🏅 Cups: {cup}', 'menu.back': 'Back', 'menu.menu': 'Menu',
    // help
    'help.title': 'How to play',
    'help.1': 'Your players run on their own. You only decide <b>when to let go of the ball</b>.',
    'help.2': 'When one of your players has the ball it <b>circles around them</b>, and an arrow shows where it would go. <b>Touch and hold anywhere</b> to keep it; <b>lift your finger</b> to send it.',
    'help.3': 'The arrow turns <b style="color:#4ade80">green</b> when it points at a team-mate (a pass) and <b style="color:#f472b6">pink</b> when it points at the goal (a shot). Releasing near a target snaps to it, so you don\'t need to be exact. The ball spins towards the most useful target first.',
    'help.4': 'Defenders who reach your carrier steal the ball. Keep it moving: pass, pass, shoot.',
    'help.5': 'Start with <b>Training</b>: the first drills have no opponents, then dummies, then defenders that get faster each level.',
    'help.6': 'The season has a league and a cup, played in five worlds. Your team\'s automatic play follows the tactics on the coach\'s board.',
    // training
    'training.title': 'Training', 'training.progress': '{done} of {total} drills done', 'training.drill': 'Drill {n}',
    'training.goalsIn': 'Score <b>{goals}</b> goals in <b>{time}</b> seconds.', 'training.start': 'Start', 'training.next': 'Next drill',
    'training.again': 'Play again', 'training.retry': 'Try again', 'training.all': 'All drills', 'training.done': 'DRILL DONE!', 'training.timeUp': "TIME'S UP",
    'training.nice': 'Nice work.', 'training.scored': 'You scored {n} of {goals}.',
    'training.none': 'No opponents', 'training.defenders': 'Defenders', 'training.dummies': 'Dummies', 'training.goalie': 'Goalie',
    'training.world': 'World: {world}',
    // coach
    'coach.title': "Coach's board", 'coach.intro': 'Tactics shape how your automatic players behave.',
    'coach.pressing': 'Pressing', 'coach.pressingHint': 'chase the ball carrier', 'coach.covering': 'Covering', 'coach.coveringHint': 'mark opponents tightly',
    'coach.pushUp': 'Push up', 'coach.pushUpHint': 'how high the team plays', 'coach.passing': 'Passing', 'coach.passingHint': 'team-mates pass rather than carry',
    'coach.shooting': 'Shooting', 'coach.shootingHint': 'shoot from distance', 'coach.settings': 'Settings', 'coach.period': 'Period length',
    'coach.spin': 'Ball spin', 'coach.spinHint': 'slower is easier · {s} s per turn', 'coach.reset': 'Reset', 'coach.save': 'Save',
    // season
    'season.next': 'Next match', 'season.league': 'League', 'season.cup': 'Cup', 'season.season': 'Season {n}',
    'season.round': 'League · Round {n}', 'season.cupRound': 'Cup · {round}', 'season.home': 'Home', 'season.away': 'Away',
    'season.play': 'Play match', 'season.recent': 'Recent results', 'season.matchday': 'Season {n} · Matchday {m} of {total}',
    'season.tbd': 'To be decided', 'season.over': 'Season {n} is over', 'season.champion': '🏆 League champion:', 'season.cupWinner': '🏅 Cup winner:',
    'season.you': " — that's you!", 'season.finished': 'You finished <b>{pos}</b> in the league.', 'season.nextSeason': 'Start next season',
    'season.qf': 'Quarter-final', 'season.sf': 'Semi-final', 'season.f': 'Final', 'season.friendly': 'Friendly', 'season.friendlyVs': 'Friendly vs {team}',
    'table.team': 'Team', 'table.p': 'P', 'table.w': 'W', 'table.d': 'D', 'table.l': 'L', 'table.gd': 'GD', 'table.pts': 'Pts',
    'ord.1': '1st', 'ord.2': '2nd', 'ord.3': '3rd', 'ord.n': '{n}th',
    // match
    'result.draw': 'DRAW', 'result.win': 'VICTORY!', 'result.loss': 'DEFEAT', 'result.ot': 'Decided in overtime',
    'result.shots': 'Shots', 'result.passes': 'Passes', 'result.steals': 'Steals', 'result.continue': 'Continue',
    'pause.title': 'Paused', 'pause.resume': 'Resume', 'pause.quit': 'Quit match',
    'hud.goals': 'GOALS', 'hud.of': 'of {n}', 'hud.vs': '{a} vs {b}',
    // engine messages (keys emitted by the engine)
    'GOAL!': 'GOAL!', 'GOAL AGAINST': 'GOAL AGAINST', 'FACE-OFF': 'FACE-OFF', 'PERIOD': 'PERIOD {n}', 'END OF PERIOD': 'END OF PERIOD {n}',
    'OFFSIDE': 'OFFSIDE', 'ICING': 'ICING', 'SUDDEN DEATH': 'SUDDEN DEATH', 'OVERTIME': 'OVERTIME', 'OVERTIME CONTINUES': 'OVERTIME CONTINUES',
    'GET READY': 'GET READY', 'AGAIN!': 'AGAIN!', 'NICE! AGAIN': 'NICE! AGAIN', 'SAVED!': 'SAVED!', 'STOLEN!': 'STOLEN!',
    'PASS FIRST!': 'PASS FIRST!', 'WRONG NET!': 'WRONG GOAL!', 'RESET': 'RESET', 'LEVEL COMPLETE!': 'DRILL DONE!', "TIME'S UP": "TIME'S UP", 'FINAL': 'FINAL',
  },
  de: {
    'menu.training': 'Training', 'menu.continue': 'Saison fortsetzen', 'menu.newSeason': 'Saison starten', 'menu.newSeason2': 'Neue Saison starten',
    'menu.quick': 'Schnelles Spiel', 'menu.coach': 'Trainer & Einstellungen', 'menu.help': 'Spielanleitung', 'menu.tagline': 'Ein Finger. Sechs Spieler. Ein Tor.',
    'menu.trophies': '🏆 Meistertitel: {league} · 🏅 Pokale: {cup}', 'menu.back': 'Zurück', 'menu.menu': 'Menü',
    'help.title': 'Spielanleitung',
    'help.1': 'Deine Spieler laufen von selbst. Du entscheidest nur, <b>wann der Ball losgelassen wird</b>.',
    'help.2': 'Hat einer deiner Spieler den Ball, <b>kreist er um ihn herum</b>, und ein Pfeil zeigt, wohin er fliegen würde. <b>Irgendwo tippen und halten</b>, um ihn zu behalten; <b>Finger heben</b>, um ihn abzuspielen.',
    'help.3': 'Der Pfeil wird <b style="color:#4ade80">grün</b>, wenn er auf einen Mitspieler zeigt (Pass), und <b style="color:#f472b6">pink</b>, wenn er aufs Tor zeigt (Schuss). Loslassen in der Nähe eines Ziels rastet ein, du musst also nicht exakt sein. Der Ball dreht sich zuerst zum nützlichsten Ziel.',
    'help.4': 'Verteidiger, die deinen Ballführer erreichen, stehlen den Ball. Halte ihn in Bewegung: passen, passen, schießen.',
    'help.5': 'Beginne mit dem <b>Training</b>: Die ersten Übungen haben keine Gegner, dann Dummys, dann Verteidiger, die mit jedem Level schneller werden.',
    'help.6': 'Die Saison hat eine Liga und einen Pokal, gespielt in fünf Welten. Das automatische Spiel deines Teams folgt der Taktik auf der Trainertafel.',
    'training.title': 'Training', 'training.progress': '{done} von {total} Übungen geschafft', 'training.drill': 'Übung {n}',
    'training.goalsIn': 'Erziele <b>{goals}</b> Tore in <b>{time}</b> Sekunden.', 'training.start': 'Los', 'training.next': 'Nächste Übung',
    'training.again': 'Nochmal spielen', 'training.retry': 'Nochmal versuchen', 'training.all': 'Alle Übungen', 'training.done': 'ÜBUNG GESCHAFFT!', 'training.timeUp': 'ZEIT ABGELAUFEN',
    'training.nice': 'Gut gemacht.', 'training.scored': 'Du hast {n} von {goals} Toren erzielt.',
    'training.none': 'Keine Gegner', 'training.defenders': 'Verteidiger', 'training.dummies': 'Dummys', 'training.goalie': 'Torwart',
    'training.world': 'Welt: {world}',
    'coach.title': 'Trainertafel', 'coach.intro': 'Die Taktik bestimmt, wie sich deine automatischen Spieler verhalten.',
    'coach.pressing': 'Pressing', 'coach.pressingHint': 'den Ballführer jagen', 'coach.covering': 'Deckung', 'coach.coveringHint': 'Gegner eng markieren',
    'coach.pushUp': 'Aufrücken', 'coach.pushUpHint': 'wie hoch das Team steht', 'coach.passing': 'Passspiel', 'coach.passingHint': 'Mitspieler passen statt zu laufen',
    'coach.shooting': 'Torschuss', 'coach.shootingHint': 'aus der Distanz schießen', 'coach.settings': 'Einstellungen', 'coach.period': 'Drittellänge',
    'coach.spin': 'Balldrehung', 'coach.spinHint': 'langsamer ist leichter · {s} s pro Umdrehung', 'coach.reset': 'Zurücksetzen', 'coach.save': 'Speichern',
    'season.next': 'Nächstes Spiel', 'season.league': 'Liga', 'season.cup': 'Pokal', 'season.season': 'Saison {n}',
    'season.round': 'Liga · Spieltag {n}', 'season.cupRound': 'Pokal · {round}', 'season.home': 'Heim', 'season.away': 'Auswärts',
    'season.play': 'Spiel starten', 'season.recent': 'Letzte Ergebnisse', 'season.matchday': 'Saison {n} · Spieltag {m} von {total}',
    'season.tbd': 'Noch offen', 'season.over': 'Saison {n} ist vorbei', 'season.champion': '🏆 Meister:', 'season.cupWinner': '🏅 Pokalsieger:',
    'season.you': ' — das bist du!', 'season.finished': 'Du hast die Liga als <b>{pos}</b> beendet.', 'season.nextSeason': 'Nächste Saison starten',
    'season.qf': 'Viertelfinale', 'season.sf': 'Halbfinale', 'season.f': 'Finale', 'season.friendly': 'Freundschaftsspiel', 'season.friendlyVs': 'Freundschaftsspiel gegen {team}',
    'table.team': 'Team', 'table.p': 'Sp', 'table.w': 'S', 'table.d': 'U', 'table.l': 'N', 'table.gd': 'TD', 'table.pts': 'Pkt',
    'ord.1': '1.', 'ord.2': '2.', 'ord.3': '3.', 'ord.n': '{n}.',
    'result.draw': 'UNENTSCHIEDEN', 'result.win': 'SIEG!', 'result.loss': 'NIEDERLAGE', 'result.ot': 'Entschieden in der Verlängerung',
    'result.shots': 'Schüsse', 'result.passes': 'Pässe', 'result.steals': 'Ballgewinne', 'result.continue': 'Weiter',
    'pause.title': 'Pause', 'pause.resume': 'Weiterspielen', 'pause.quit': 'Spiel beenden',
    'hud.goals': 'TORE', 'hud.of': 'von {n}', 'hud.vs': '{a} gegen {b}',
    'GOAL!': 'TOR!', 'GOAL AGAINST': 'GEGENTOR', 'FACE-OFF': 'BULLY', 'PERIOD': '{n}. DRITTEL', 'END OF PERIOD': 'ENDE {n}. DRITTEL',
    'OFFSIDE': 'ABSEITS', 'ICING': 'ICING', 'SUDDEN DEATH': 'SUDDEN DEATH', 'OVERTIME': 'VERLÄNGERUNG', 'OVERTIME CONTINUES': 'VERLÄNGERUNG GEHT WEITER',
    'GET READY': 'BEREIT MACHEN', 'AGAIN!': 'NOCHMAL!', 'NICE! AGAIN': 'SUPER! NOCHMAL', 'SAVED!': 'GEHALTEN!', 'STOLEN!': 'GEKLAUT!',
    'PASS FIRST!': 'ERST PASSEN!', 'WRONG NET!': 'FALSCHES TOR!', 'RESET': 'NEUSTART', 'LEVEL COMPLETE!': 'ÜBUNG GESCHAFFT!', "TIME'S UP": 'ZEIT ABGELAUFEN', 'FINAL': 'ENDE',
  },
};

/** Translate a key, substituting {params}. Falls back to English, then to the key. */
export function t(key, params) {
  let s = S[LANG][key] ?? S.en[key] ?? key;
  if (params) for (const k of Object.keys(params)) s = s.split(`{${k}}`).join(params[k]);
  return s;
}

/** Pick the current language from a localised object like { en: '...', de: '...' }. */
export function tl(obj) {
  if (obj == null) return '';
  if (typeof obj === 'string') return obj;
  return obj[LANG] ?? obj.en ?? Object.values(obj)[0] ?? '';
}

export function ordinal(n) {
  return n <= 3 ? t(`ord.${n}`) : t('ord.n', { n });
}
