import { Gift, ShieldOff, Ban, Code2, type LucideIcon } from "lucide-react";
import { Reveal } from "./Reveal";

const POINTS: { icon: LucideIcon; title: string; body: string }[] = [
  { icon: Gift, title: "Free forever", body: "No paywalls, no premium tier, no trial timer." },
  { icon: Ban, title: "Zero ads", body: "Your workout, not an ad break between sets." },
  { icon: ShieldOff, title: "No SDKs", body: "No trackers or third-party analytics shipped." },
  { icon: Code2, title: "Open source", body: "Read every line and build it yourself." },
];

export function Why() {
  return (
    <section className="py-16">
      <div className="mx-auto max-w-6xl px-5 sm:px-8">
        <div className="grid grid-cols-2 gap-6 rounded-3xl border border-line bg-surface/40 p-8 sm:p-10 lg:grid-cols-4">
          {POINTS.map(({ icon: Icon, title, body }, i) => (
            <Reveal key={title} delay={i * 70}>
              <div>
                <Icon className="size-6 text-lime" strokeWidth={2} />
                <h3 className="mt-3 text-base font-semibold text-fg">{title}</h3>
                <p className="mt-1 text-sm leading-relaxed text-muted">{body}</p>
              </div>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}
