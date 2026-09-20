import { Flame, Trophy, Weight } from "lucide-react";
import { GithubIcon } from "./Icons";
import { PhoneFrame } from "./PhoneFrame";
import { SITE } from "@/lib/site";

const PROOF = [
  { icon: Flame, value: "5 days", label: "current streak" },
  { icon: Trophy, value: "New PR", label: "Bench 85 kg × 6" },
  { icon: Weight, value: "43.9k kg", label: "total volume" },
];

export function Hero() {
  return (
    <section id="top" className="relative pt-32 pb-16 sm:pt-40 lg:pb-24">
      {/* One soft lime wash across the top — the only decoration in the fold */}
      <div
        aria-hidden="true"
        className="pointer-events-none absolute inset-x-0 top-0 h-[520px] bg-[radial-gradient(70%_55%_at_50%_0%,rgba(212,255,74,0.10),transparent_70%)]"
      />

      <div className="page relative grid items-center gap-14 lg:grid-cols-[minmax(0,1.1fr)_minmax(0,0.9fr)] lg:gap-20">
        {/* Copy */}
        <div className="text-center lg:text-left">
          <span className="inline-flex items-center gap-2 rounded-full border border-line px-3 py-1 text-xs font-medium text-muted">
            <span className="size-1.5 rounded-full bg-lime" />
            iOS app + web PWA · free &amp; open source
          </span>

          <h1 className="mt-7 font-display text-[3rem] leading-[0.92] text-fg sm:text-7xl lg:text-[5.75rem] xl:text-[6.5rem]">
            Track your gains.
            <br />
            <span className="text-lime">Own your progress.</span>
          </h1>

          <p className="mx-auto mt-7 max-w-lg text-lg leading-relaxed text-muted lg:mx-0">
            A fast, no-nonsense gym tracker. Log every set, run any split, and
            watch your PRs and streaks grow — with a lock-screen Live Activity
            so you never break your flow.
          </p>

          <div className="mt-9 flex flex-col items-center gap-3 sm:flex-row lg:justify-start">
            <a
              href="#get"
              className="w-full rounded-xl bg-lime px-6 py-3.5 text-center text-base font-semibold text-ink transition-transform hover:scale-[1.02] active:scale-[0.98] sm:w-auto"
            >
              Get IronLog free
            </a>
            <a
              href={SITE.github}
              target="_blank"
              rel="noreferrer"
              className="inline-flex w-full items-center justify-center gap-2 rounded-xl border border-line px-6 py-3.5 text-base font-semibold text-fg transition-colors hover:border-white/25 sm:w-auto"
            >
              <GithubIcon className="size-5" />
              View source
            </a>
          </div>

          <p className="mt-5 text-sm text-muted-2">
            No ads · No account required · No third-party SDKs
          </p>

          {/* Proof, in a row instead of floating over the screenshot */}
          <ul className="mx-auto mt-12 grid max-w-md grid-cols-3 divide-x divide-line border-y border-line lg:mx-0 lg:max-w-none">
            {PROOF.map(({ icon: Icon, value, label }) => (
              <li key={value} className="px-3 py-4 text-left first:pl-0 sm:px-5 sm:first:pl-0">
                <span className="flex items-center gap-2 text-base font-semibold text-fg sm:text-lg">
                  <Icon className="size-4 shrink-0 text-lime" strokeWidth={2.25} />
                  {value}
                </span>
                <span className="mt-1 block text-xs text-muted-2 sm:text-sm">{label}</span>
              </li>
            ))}
          </ul>
        </div>

        {/* Product visual on its own stage, rising out of the panel's bottom edge */}
        <div className="relative mx-auto w-full max-w-[440px] lg:max-w-none">
          <div className="overflow-hidden rounded-[2rem] border border-line bg-surface/60 px-8 pt-10 sm:px-14 sm:pt-14 lg:px-16 lg:pt-16">
            <div className="mx-auto max-h-[520px] max-w-[300px] sm:max-h-[600px] sm:max-w-[320px]">
              <PhoneFrame
                src="/screenshots/02-log.png"
                alt="IronLog logging a Push workout with a running rest timer"
                priority
                sizes="(max-width: 1024px) 68vw, 320px"
              />
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
