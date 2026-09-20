import {
  Dumbbell,
  LayoutGrid,
  ListChecks,
  Timer,
  Trophy,
  Smartphone,
  Cloud,
  Droplet,
  type LucideIcon,
} from "lucide-react";
import { Reveal } from "./Reveal";

type Feature = { icon: LucideIcon; title: string; body: string };

const FEATURES: Feature[] = [
  {
    icon: Dumbbell,
    title: "80+ exercises",
    body: "Seven muscle groups, each with sensible sets, reps and form tips baked in.",
  },
  {
    icon: LayoutGrid,
    title: "Any split",
    body: "Full Body, PPL, Upper/Lower, Bro Split — or freestyle a workout on the spot.",
  },
  {
    icon: ListChecks,
    title: "Fast set logger",
    body: "Weight and reps per set, tap to mark done. Last time's numbers sit right beside each set.",
  },
  {
    icon: Timer,
    title: "Smart rest timer",
    body: "Restarts fresh the moment you finish a set, so every rest is a clean countdown.",
  },
  {
    icon: Trophy,
    title: "PRs & stats",
    body: "Auto-detected personal records, day streaks, weekly consistency and total volume.",
  },
  {
    icon: Smartphone,
    title: "Lock-screen logging",
    body: "Log sets from the Lock Screen and Dynamic Island — no unlock, no broken flow.",
  },
  {
    icon: Cloud,
    title: "Cloud sync",
    body: "Email sign-in with Supabase and row-level security. Local-first, synced when you are.",
  },
  {
    icon: Droplet,
    title: "Water tracker",
    body: "A daily 8-glass counter, because recovery counts as much as the lift.",
  },
];

export function Features() {
  return (
    <section id="features" className="border-t border-line/60 py-24 lg:py-32">
      <div className="page">
        <Reveal>
          <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)] lg:items-end lg:gap-16">
            <div>
              <p className="eyebrow">Built for lifters</p>
              <h2 className="mt-4 font-display text-5xl text-fg sm:text-6xl">
                Everything you need.
                <br />
                Nothing you don&apos;t.
              </h2>
            </div>
            <p className="max-w-lg text-lg leading-relaxed text-muted lg:justify-self-end lg:pb-1">
              Eight things, done properly. All of them work offline, from the
              first session, without an account.
            </p>
          </div>
        </Reveal>

        <div className="mt-16 grid grid-cols-1 gap-px overflow-hidden rounded-3xl border border-line bg-line sm:grid-cols-2 lg:grid-cols-4">
          {FEATURES.map(({ icon: Icon, title, body }, i) => (
            <Reveal key={title} delay={(i % 4) * 70}>
              <div className="group h-full bg-ink p-6 transition-colors hover:bg-surface lg:p-7">
                <span className="grid size-11 place-items-center rounded-xl bg-lime/10 ring-1 ring-lime/20 transition-colors group-hover:bg-lime/15">
                  <Icon className="size-5 text-lime" strokeWidth={2} />
                </span>
                <h3 className="mt-4 text-base font-semibold text-fg">{title}</h3>
                <p className="mt-1.5 text-sm leading-relaxed text-muted">{body}</p>
              </div>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}
