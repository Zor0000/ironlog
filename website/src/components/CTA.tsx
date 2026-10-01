import { Reveal } from "./Reveal";
import { AppStoreDownload } from "./AppStoreDownload";

export function CTA() {
  return (
    <section id="get" className="border-t border-line/60 py-24 lg:py-32">
      <div className="page">
        <Reveal>
          <div className="relative overflow-hidden rounded-[2rem] border border-line bg-surface/60 px-6 py-16 text-center sm:px-12 lg:py-20">
            <div
              aria-hidden="true"
              className="pointer-events-none absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-lime/60 to-transparent"
            />
            <h2 className="relative mx-auto max-w-2xl font-display text-5xl text-fg sm:text-6xl">
              Ready to own your progress?
            </h2>
            <p className="relative mx-auto mt-4 max-w-lg text-lg text-muted">
              Setzo is coming soon to the App Store. Log workouts on your
              iPhone, with optional cloud sync when you want it.
            </p>

            <div className="relative mt-9 flex flex-col items-center justify-center gap-3 sm:flex-row">
              <AppStoreDownload className="w-full sm:w-auto" />
            </div>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
