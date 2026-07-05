import Image from "next/image";

type Props = {
  src: string;
  alt: string;
  priority?: boolean;
  sizes?: string;
  className?: string;
};

/**
 * A crisp CSS iPhone bezel around a real app screenshot. The captured
 * screenshots already include the status bar and Dynamic Island, so the frame
 * only adds the titanium rail, black bezel and rounded screen.
 */
export function PhoneFrame({ src, alt, priority, sizes, className = "" }: Props) {
  return (
    <div className={`relative ${className}`}>
      {/* Titanium outer rail */}
      <div className="rounded-[2.7rem] bg-gradient-to-b from-[#3a3a3e] via-[#202024] to-[#111114] p-[3px] shadow-[0_50px_90px_-30px_rgba(0,0,0,0.9)] ring-1 ring-white/10">
        {/* Black bezel */}
        <div className="rounded-[2.55rem] bg-black p-[7px]">
          <div className="relative aspect-[1206/2622] overflow-hidden rounded-[2rem] bg-black">
            <Image
              src={src}
              alt={alt}
              fill
              priority={priority}
              sizes={sizes ?? "(max-width: 768px) 68vw, 320px"}
              className="object-cover object-top"
            />
            {/* Faint screen glare */}
            <div className="pointer-events-none absolute inset-0 bg-gradient-to-tr from-transparent via-white/0 to-white/[0.06]" />
          </div>
        </div>
      </div>
    </div>
  );
}
