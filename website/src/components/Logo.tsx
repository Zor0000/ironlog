export function LogoMark({ className = "" }: { className?: string }) {
  return (
    <svg viewBox="0 0 32 32" className={className} aria-hidden="true">
      <rect x="1" y="10" width="6" height="12" rx="2" fill="currentColor" />
      <rect x="7" y="12" width="3" height="8" rx="1" fill="currentColor" />
      <rect x="10" y="14" width="12" height="4" rx="1" fill="currentColor" />
      <rect x="22" y="12" width="3" height="8" rx="1" fill="currentColor" />
      <rect x="25" y="10" width="6" height="12" rx="2" fill="currentColor" />
    </svg>
  );
}

export function Logo({ className = "" }: { className?: string }) {
  return (
    <span className={`inline-flex items-center gap-2.5 ${className}`}>
      <span className="grid size-8 place-items-center rounded-[9px] bg-ink ring-1 ring-line">
        <LogoMark className="w-5 text-lime" />
      </span>
      <span className="font-display text-2xl tracking-wide text-fg">
        Iron<span className="text-lime">Log</span>
      </span>
    </span>
  );
}
