import { PhoneFrame } from "./PhoneFrame";
import { Reveal } from "./Reveal";
import { SHOTS } from "@/lib/site";

export function Showcase() {
  return (
    <section id="screens" className="relative py-24">
      <div className="mx-auto max-w-6xl px-5 sm:px-8">
        <Reveal className="mx-auto max-w-2xl text-center">
          <p className="text-sm font-semibold uppercase tracking-[0.2em] text-lime">
            Every screen, dialed in
          </p>
          <h2 className="mt-3 font-display text-5xl text-fg sm:text-6xl">
            See it in action
          </h2>
          <p className="mt-4 text-lg text-muted">
            Real screenshots — no mockup fluff. This is exactly what training with
            IronLog looks like.
          </p>
        </Reveal>

        <div className="mt-16 grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-4">
          {SHOTS.map((shot, i) => (
            <Reveal key={shot.src} delay={i * 90}>
              <article className="group relative flex h-full flex-col overflow-hidden rounded-3xl border border-line bg-gradient-to-b from-surface to-ink px-5 pt-6 pb-0">
                <div
                  aria-hidden="true"
                  className="pointer-events-none absolute inset-x-0 -top-16 h-40 bg-[radial-gradient(60%_100%_at_50%_0%,rgba(212,255,74,0.14),transparent_70%)]"
                />
                <p className="relative text-xs font-semibold uppercase tracking-[0.18em] text-lime">
                  {shot.label}
                </p>
                <h3 className="relative mt-2 text-lg font-semibold leading-snug text-fg">
                  {shot.headline}
                </h3>
                <div className="relative mt-6 -mb-10 px-3 transition-transform duration-500 group-hover:-translate-y-2">
                  <PhoneFrame
                    src={shot.src}
                    alt={shot.alt}
                    sizes="(max-width: 640px) 80vw, (max-width: 1024px) 40vw, 240px"
                  />
                </div>
              </article>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}
