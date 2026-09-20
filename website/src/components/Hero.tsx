import { Flame, Trophy } from "lucide-react";
import { GithubIcon } from "./Icons";
import { PhoneFrame } from "./PhoneFrame";
import { SITE } from "@/lib/site";

export function Hero() {
  return (
    <section id="top" className="relative overflow-hidden pt-28 pb-20 sm:pt-36">
      {/* Lime glow + vignette */}
      <div
        aria-hidden="true"
        className="pointer-events-none absolute inset-x-0 -top-40 h-[560px] bg-[radial-gradient(60%_60%_at_50%_0%,rgba(212,255,74,0.16),transparent_70%)]"
      />
      <div
        aria-hidden="true"
        className="pointer-events-none absolute inset-0 bg-[radial-gradient(120%_80%_at_50%_-10%,transparent_40%,rgba(0,0,0,0.6))]"
      />

      <div className="mx-auto grid max-w-6xl items-center gap-12 px-5 sm:px-8 lg:grid-cols-[1.05fr_0.95fr]">
        {/* Copy */}
        <div className="text-center lg:text-left">
          <span className="inline-flex items-center gap-2 rounded-full border border-line bg-surface/60 px-3 py-1 text-xs font-medium text-muted">
            <span className="size-1.5 rounded-full bg-lime" />
            iOS app + web PWA · free &amp; open source
          </span>

          <h1 className="mt-6 font-display text-6xl text-fg sm:text-7xl lg:text-[5.5rem]">
            Track your gains.
            <br />
            <span className="text-lime">Own your progress.</span>
          </h1>

          <p className="mx-auto mt-6 max-w-md text-lg leading-relaxed text-muted lg:mx-0">
            A fast, no-nonsense gym tracker. Log every set, run any split, and
            watch your PRs and streaks grow — with a lock-screen Live Activity so
            you never break your flow.
          </p>

          <div className="mt-8 flex flex-col items-center gap-3 sm:flex-row lg:justify-start">
            <a
              href="#get"
              className="w-full rounded-xl bg-lime px-6 py-3.5 text-center text-base font-semibold text-ink transition-transform hover:scale-[1.03] active:scale-95 sm:w-auto"
            >
              Get IronLog free
            </a>
            <a
              href={SITE.github}
              target="_blank"
              rel="noreferrer"
              className="inline-flex w-full items-center justify-center gap-2 rounded-xl border border-line bg-surface/60 px-6 py-3.5 text-base font-semibold text-fg transition-colors hover:border-white/25 sm:w-auto"
            >
              <GithubIcon className="size-5" />
              View source
            </a>
          </div>

          <p className="mt-6 text-sm text-muted-2">
            No ads · No account required · No third-party SDKs
          </p>
        </div>

        {/* Phone + floating chips */}
        <div className="relative mx-auto w-full max-w-[320px]">
          <div className="animate-float">
            <PhoneFrame
              src="/screenshots/02-log.png"
              alt="IronLog logging a Push workout with a running rest timer"
              priority
              sizes="(max-width: 1024px) 68vw, 320px"
            />
          </div>

          <FloatingChip
            className="-left-6 top-16 sm:-left-10"
            icon={<Flame className="size-4 text-lime" />}
            title="5 day streak"
            sub="keep it going"
          />
          <FloatingChip
            className="-right-4 top-1/2 sm:-right-10"
            icon={<Trophy className="size-4 text-lime" />}
            title="New PR"
            sub="Bench 85 kg × 6"
          />
          <FloatingChip
            className="bottom-10 -left-4 sm:-left-8"
            icon={<span className="text-sm font-bold text-lime">43.9k</span>}
            title="Total volume"
            sub="kg lifted"
          />
        </div>
      </div>
    </section>
  );
}

function FloatingChip({
  className = "",
  icon,
  title,
  sub,
}: {
  className?: string;
  icon: React.ReactNode;
  title: string;
  sub: string;
}) {
  return (
    <div
      className={`absolute z-10 flex items-center gap-2.5 rounded-xl border border-line bg-surface/80 px-3 py-2 shadow-xl backdrop-blur-md ${className}`}
    >
      <span className="grid size-8 place-items-center rounded-lg bg-ink ring-1 ring-line">
        {icon}
      </span>
      <span className="leading-tight">
        <span className="block text-sm font-semibold text-fg">{title}</span>
        <span className="block text-xs text-muted-2">{sub}</span>
      </span>
    </div>
  );
}
