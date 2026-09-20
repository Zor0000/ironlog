import { PhoneFrame } from "./PhoneFrame";
import { Reveal } from "./Reveal";
import { SHOTS } from "@/lib/site";

export function Showcase() {
  return (
    <section id="screens" className="border-t border-line/60 py-24 lg:py-32">
      <div className="page">
        <Reveal className="mx-auto max-w-2xl text-center">
          <p className="eyebrow">Every screen, dialed in</p>
          <h2 className="mt-4 font-display text-5xl text-fg sm:text-6xl">
            See it in action
          </h2>
          <p className="mt-5 text-lg text-muted">
            Real screenshots — no mockup fluff. This is exactly what training with
            IronLog looks like.
          </p>
        </Reveal>

        <div className="mt-16 grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-4">
          {SHOTS.map((shot, i) => (
            <Reveal key={shot.src} delay={i * 90}>
              <article className="group relative flex h-full flex-col overflow-hidden rounded-3xl border border-line bg-surface/60 px-5 pt-6 pb-0">
                <p className="relative text-xs font-semibold uppercase tracking-[0.18em] text-lime">
                  {shot.label}
                </p>
                <h3 className="relative mt-2 text-lg font-semibold leading-snug text-fg">
                  {shot.headline}
                </h3>
                <div className="relative mt-6 -mb-12 px-3 transition-transform duration-500 group-hover:-translate-y-2 motion-reduce:transition-none motion-reduce:group-hover:translate-y-0">
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
