// Global game constants. Units are metres, the rink's long axis is Z.
// Team 0 (the user) defends the goal at -Z and attacks towards +Z.

export const RINK = {
  length: 60,        // full length along Z
  width: 30,         // full width along X
  corner: 8.5,       // corner radius of the boards
  goalLineZ: 26,     // distance of each goal line from centre
  blueLineZ: 9.5,    // distance of each blue line from centre
  goalWidth: 5.2,    // stylised, wider than real life so shots can go in
  goalDepth: 1.6,
  creaseRadius: 3.2,
  faceoffRadius: 4.5,
  boardHeight: 1.1,
};

export const PLAYER = {
  radius: 0.8,
  goalieRadius: 1.0,
  reach: 1.45,        // distance at which a skater picks up a loose puck
  stealReach: 1.05,   // distance to the puck at which a defender steals it
  carryOffset: 1.15,  // where the puck sits in front of a carrier
  humanSpeed: 8.6,
  aiSpeedBase: 6.2,   // scaled by rating
  goalieSpeed: 6.0,
  accel: 38,
};

export const PUCK = {
  radius: 0.36,
  friction: 0.45,     // m/s^2 of deceleration on ice
  drag: 0.12,         // proportional velocity loss per second
  maxSpeed: 30,
  boardRestitution: 0.72,
  playerRestitution: 0.85,
};

export const RULES = {
  periods: 3,
  periodSeconds: 120,   // default; changed in settings
  faceoffDelay: 1.3,
  goalCelebration: 3.2,
  whistleDelay: 1.4,
  overtimeSuddenDeath: true,
};

export const DEFAULT_TACTICS = {
  pressing: 0.55,   // how many players chase the carrier and how far out
  covering: 0.55,   // how strictly free players mark opponents
  pushUp: 0.55,     // how high the whole team pushes towards the puck
  passing: 0.55,    // how willing the carrier is to pass rather than carry
  shooting: 0.55,   // how eagerly the carrier shoots from range
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

export const SAVE_KEY = 'slapshot-league-save-v1';
export const SETTINGS_KEY = 'slapshot-league-settings-v1';
