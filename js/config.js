// Global game constants. Units are metres, the rink's long axis is Z.
// Team 0 (the user) defends the goal at -Z and attacks towards +Z.

// The two sports share one engine. Field hockey (grass, ball, square-ish
// pitch) is the default; the Himalaya world plays ice hockey (ice, puck,
// rounded boards).
export const SPORTS = {
  field: {
    id: 'field', corner: 2.0, friction: 0.9, drag: 0.3, wallRestitution: 0.6,
    ballRadius: 0.36, ball: 'ball', shotSpeedBoost: 1.0,
  },
  ice: {
    id: 'ice', corner: 8.5, friction: 0.45, drag: 0.2, wallRestitution: 0.72,
    ballRadius: 0.36, ball: 'puck', shotSpeedBoost: 1.0,
  },
};

export const RINK = {
  length: 60,        // full length along Z
  width: 30,         // full width along X
  corner: 8.5,       // default corner radius (ice); a match uses its sport's value
  goalLineZ: 26,     // distance of each goal line from centre
  blueLineZ: 9.5,    // distance of each blue line from centre
  goalWidth: 6.0,    // stylised, wider than real life so shots can go in
  goalDepth: 1.6,
  creaseRadius: 3.2,
  faceoffRadius: 4.5,
  boardHeight: 1.1,
};

export const PLAYER = {
  radius: 0.8,
  goalieRadius: 1.0,
  reach: 1.45,        // distance at which a skater picks up a loose puck
  stealReach: 0.9,    // distance to the puck at which a defender steals it
  stealTime: 0.18,    // seconds of contact with the puck before it is stolen
  settleTime: 0.45,   // grace after winning the ball, so it cannot ping-pong
  aiSpeedBase: 6.2,   // scaled by rating
  goalieSpeed: 4.8,
  goalieReaction: 0.16, // seconds before a goalie reacts to a shot (+ more for low skill)
  accel: 38,
};

// The puck circles the carrier; lifting the finger releases it along the
// line from the carrier through the puck.
export const ORBIT = {
  radius: 1.5,
  period: 2.0,             // seconds per revolution (settings can change it)
  assistPass: 0.36,        // radians: snap to a team-mate within this angle
  assistGoal: 0.40,        // radians: snap to the goal within this angle
  // One release, one speed: a shot on goal always leaves as hard as possible,
  // and a pass gets faster the further it has to travel.
  shotSpeed: 30,           // every shot on goal, both sides
  freeSpeed: 24,           // release with nothing to snap to
  passSpeedMin: 14,        // a short square ball
  passSpeedMax: 30,        // a long ball is hit as hard as a shot
  passSpeedPerMetre: 0.85,
};

export const PUCK = {
  radius: 0.36,
  friction: 0.45,     // m/s^2 of deceleration on ice
  drag: 0.2,          // proportional velocity loss per second
  maxSpeed: 30,
  boardRestitution: 0.72,
  playerRestitution: 0.85,
};

export const RULES = {
  periods: 3,
  periodSeconds: 120,   // default; changed in settings
  faceoffDelay: 1.3,
  goalCelebration: 3.0,
  whistleDelay: 1.4,
  overtimeSuddenDeath: true,
  offside: false,       // arcade defaults; the engine still supports both
  icing: false,
  drillReady: 1.4,      // training: pause before a drill starts (camera settles)
  drillGoal: 1.6,       // training: celebration before the drill resets
  drillLost: 1.2,       // training: pause after losing the puck
};

export const DEFAULT_TACTICS = {
  pressing: 0.55,   // how many players chase the carrier and how far out
  covering: 0.55,   // how strictly free players mark opponents
  pushUp: 0.55,     // how high the whole team pushes towards the puck
  passing: 0.55,    // how willing the carrier is to pass rather than carry
  shooting: 0.55,   // how eagerly the carrier shoots from range
  discipline: 0.0,  // 0 = follow the play freely, 1 = hold the prescribed zone
};

// Faceoff dots: centre, four neutral zone dots, four end zone dots.
export const FACEOFF_SPOTS = {
  center: { x: 0, z: 0 },
  neutral: [
    { x: -7, z: -7 }, { x: 7, z: -7 }, { x: -7, z: 7 }, { x: 7, z: 7 },
  ],
  end: [
    { x: -7, z: -20 }, { x: 7, z: -20 }, { x: -7, z: 20 }, { x: 7, z: 20 },
  ],
};

export const SAVE_KEY = 'slapshot-league-save-v2';
export const SETTINGS_KEY = 'slapshot-league-settings-v2';
export const TRAINING_KEY = 'slapshot-league-training-v1';
