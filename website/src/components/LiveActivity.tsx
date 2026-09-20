import {
  Dumbbell,
  Timer,
  Check,
  ChevronLeft,
  ChevronRight,
  Minus,
  Plus,
  Lock,
} from "lucide-react";
import { Reveal } from "./Reveal";

export function LiveActivity() {
  return (
    <section id="live-activity" className="relative overflow-hidden py-24">
      <div
        aria-hidden="true"
        className="pointer-events-none absolute left-1/2 top-1/2 h-[520px] w-[520px] -translate-x-1/2 -translate-y-1/2 rounded-full bg-[radial-gradient(circle,rgba(212,255,74,0.10),transparent_65%)]"
      />
      <div className="mx-auto grid max-w-6xl items-center gap-14 px-5 sm:px-8 lg:grid-cols-2">
        {/* Copy */}
        <Reveal>
          <p className="text-sm font-semibold uppercase tracking-[0.2em] text-lime">
            The killer feature
          </p>
          <h2 className="mt-3 font-display text-5xl text-fg sm:text-6xl">
            Log a set without
            <br />
            <span className="text-lime">unlocking your phone.</span>
          </h2>
          <p className="mt-5 max-w-md text-lg leading-relaxed text-muted">
            IronLog puts a live workout card on your Lock Screen and in the
            Dynamic Island. Dial in the weight and reps, tap{" "}
            <span className="font-semibold text-fg">Log set</span>, and the rest
            timer restarts — all between sets, without ever breaking your flow.
          </p>
          <ul className="mt-7 space-y-3">
            {[
              "Big weight & reps steppers, sized for chalky thumbs",
              "The rest timer counts down right on your Lock Screen",
              "Move between exercises without opening the app",
            ].map((item) => (
              <li key={item} className="flex items-start gap-3 text-fg">
                <span className="mt-0.5 grid size-5 shrink-0 place-items-center rounded-full bg-lime/15">
                  <Check className="size-3 text-lime" strokeWidth={3} />
                </span>
                <span className="text-[15px] text-muted">{item}</span>
              </li>
            ))}
          </ul>
        </Reveal>

        {/* Lock screen mock */}
        <Reveal delay={120} className="flex justify-center">
          <LockScreen />
        </Reveal>
      </div>
    </section>
  );
}

function LockScreen() {
  return (
    <div className="relative w-full max-w-[360px] rounded-[2.6rem] border border-white/10 bg-gradient-to-b from-[#0e0e10] via-[#0b0b0c] to-black p-3 shadow-[0_50px_100px_-30px_rgba(0,0,0,0.9)]">
      <div className="flex min-h-[600px] flex-col rounded-[2.1rem] bg-[radial-gradient(120%_60%_at_50%_0%,rgba(212,255,74,0.08),transparent_60%)] px-5 pb-5 pt-8">
        {/* Status glyphs */}
        <div className="flex items-center justify-center text-muted-2">
          <Lock className="size-4" />
        </div>
        {/* Clock */}
        <div className="mt-3 text-center">
          <div className="font-display text-[5.5rem] leading-none text-fg">
            9:41
          </div>
          <div className="mt-1 text-sm text-muted-2">Sunday, July 5</div>
        </div>

        <div className="mt-auto pt-8">
          <LiveActivityCard />
        </div>
      </div>
      {/* Home indicator */}
      <div className="mx-auto mt-2 mb-1 h-1 w-28 rounded-full bg-white/25" />
    </div>
  );
}

/** Faithful recreation of IronLogWidget/WorkoutLiveActivity.swift LockScreenView. */
function LiveActivityCard() {
  return (
    <div className="rounded-2xl bg-[#121214] p-4 shadow-2xl ring-1 ring-white/[0.06]">
      {/* Header */}
      <div className="flex items-center gap-2.5">
        <span className="grid size-8 shrink-0 place-items-center rounded-[10px] bg-lime">
          <Dumbbell className="size-4 text-ink" strokeWidth={2.5} />
        </span>
        <div className="min-w-0 flex-1">
          <div className="truncate text-[13.5px] font-bold text-[#f5f5f5]">
            Barbell Bench Press
          </div>
          <div className="mt-1 flex items-center gap-1.5">
            <span className="h-1.5 w-1.5 rounded-full bg-lime" />
            <span className="h-1.5 w-1.5 rounded-full bg-lime" />
            <span className="h-1.5 w-3.5 rounded-full bg-white/55" />
            <span className="ml-1 truncate text-[11px] text-[#9e9ea3]">
              Set 3/3 · PPL
            </span>
          </div>
        </div>
        {/* Rest badge */}
        <span className="inline-flex shrink-0 items-center gap-1.5 rounded-full border border-lime/25 bg-lime/[0.14] px-2.5 py-1.5 text-lime">
          <Timer className="size-3.5" strokeWidth={2.5} />
          <span className="text-sm font-semibold tabular-nums">1:08</span>
        </span>
      </div>

      {/* Steppers */}
      <div className="mt-3 grid grid-cols-2 gap-2">
        <Stepper label="KG" value="85" />
        <Stepper label="REPS" value="5" />
      </div>

      {/* Actions */}
      <div className="mt-2 flex items-center gap-2">
        <button className="grid size-9 place-items-center rounded-xl bg-white/[0.11] text-[#f5f5f5]">
          <ChevronLeft className="size-4" strokeWidth={2.5} />
        </button>
        <button className="flex h-9 flex-1 items-center justify-center gap-1.5 rounded-xl bg-lime text-[15px] font-semibold text-ink">
          <Check className="size-4" strokeWidth={3} />
          Log set
        </button>
        <button className="grid size-9 place-items-center rounded-xl bg-white/[0.11] text-[#f5f5f5]">
          <ChevronRight className="size-4" strokeWidth={2.5} />
        </button>
      </div>
    </div>
  );
}

function Stepper({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-xl bg-white/[0.05] px-2.5 py-1.5 ring-1 ring-white/[0.09]">
      <div className="text-center text-[10px] font-semibold tracking-wider text-[#9e9ea3]">
        {label}
      </div>
      <div className="mt-1 flex items-center justify-between">
        <span className="grid size-8 place-items-center rounded-lg bg-white/[0.13] text-[#f5f5f5]">
          <Minus className="size-3.5" strokeWidth={2.5} />
        </span>
        <span className="text-[22px] font-bold tabular-nums text-[#f5f5f5]">
          {value}
        </span>
        <span className="grid size-8 place-items-center rounded-lg bg-white/[0.13] text-[#f5f5f5]">
          <Plus className="size-3.5" strokeWidth={2.5} />
        </span>
      </div>
    </div>
  );
}
