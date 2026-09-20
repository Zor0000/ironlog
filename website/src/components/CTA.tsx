import { Globe } from "lucide-react";
import { GithubIcon, AppleIcon } from "./Icons";
import { Reveal } from "./Reveal";
import { SITE } from "@/lib/site";

export function CTA() {
  return (
    <section id="get" className="relative py-24">
      <div className="mx-auto max-w-6xl px-5 sm:px-8">
        <Reveal>
          <div className="relative overflow-hidden rounded-[2rem] border border-lime/20 bg-gradient-to-b from-surface to-ink px-6 py-16 text-center sm:px-12">
            <div
              aria-hidden="true"
              className="pointer-events-none absolute inset-x-0 -top-24 h-64 bg-[radial-gradient(50%_100%_at_50%_0%,rgba(212,255,74,0.22),transparent_70%)]"
            />
            <h2 className="relative mx-auto max-w-2xl font-display text-5xl text-fg sm:text-6xl">
              Ready to own your progress?
            </h2>
            <p className="relative mx-auto mt-4 max-w-lg text-lg text-muted">
              Clone the repo, point it at a free Supabase project, and you&apos;re
              lifting in minutes — on iPhone and the web.
            </p>

            <div className="relative mt-9 flex flex-col items-center justify-center gap-3 sm:flex-row">
              <a
                href={SITE.github}
                target="_blank"
                rel="noreferrer"
                className="inline-flex w-full items-center justify-center gap-2 rounded-xl bg-lime px-7 py-3.5 text-base font-semibold text-ink transition-transform hover:scale-[1.03] active:scale-95 sm:w-auto"
              >
                <GithubIcon className="size-5" />
                Get it on GitHub
              </a>
              <div className="flex items-center gap-4 text-sm text-muted-2">
                <span className="inline-flex items-center gap-1.5">
                  <AppleIcon className="size-4" /> iOS app
                </span>
                <span className="inline-flex items-center gap-1.5">
                  <Globe className="size-4" /> Web PWA
                </span>
              </div>
            </div>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
