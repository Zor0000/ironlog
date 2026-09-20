export const SITE = {
  name: "IronLog",
  tagline: "Track your gains. Own your progress.",
  description:
    "A fast, free, no-nonsense gym tracker. Log every set, run any split, and watch your PRs and streaks grow.",
  github: "https://github.com/Zor0000/ironlog",
};

export const NAV_LINKS = [
  { label: "Features", href: "#features" },
  { label: "Screens", href: "#screens" },
  { label: "Live Activity", href: "#live-activity" },
];

export type Shot = {
  src: string;
  alt: string;
  label: string;
  headline: string;
};

// App Store–style framed slides (label + headline + device), designed in the
// app-store-screenshots skill and rendered here natively for full fidelity.
export const SHOTS: Shot[] = [
  {
    src: "/screenshots/02-log.png",
    alt: "IronLog set logger with a running rest timer and completed sets",
    label: "Log every set",
    headline: "Weight, reps and rest — logged in seconds.",
  },
  {
    src: "/screenshots/01-workouts.png",
    alt: "IronLog split picker showing Full Body, PPL, Upper/Lower and more",
    label: "Pick your split",
    headline: "Full Body, PPL, Upper/Lower & more.",
  },
  {
    src: "/screenshots/04-stats.png",
    alt: "IronLog stats screen with sessions, day streak, volume and personal records",
    label: "See progress",
    headline: "Streaks, PRs and volume, visualized.",
  },
  {
    src: "/screenshots/03-history.png",
    alt: "IronLog history screen listing past workout sessions synced to the cloud",
    label: "Never forget a lift",
    headline: "Every session, synced to the cloud.",
  },
];
