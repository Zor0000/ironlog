import { GithubIcon } from "./Icons";
import { Logo } from "./Logo";
import { NAV_LINKS, SITE } from "@/lib/site";

export function Nav() {
  return (
    <header className="fixed inset-x-0 top-0 z-50 border-b border-line/60 bg-ink/70 backdrop-blur-xl">
      <nav className="mx-auto flex h-16 max-w-6xl items-center justify-between px-5 sm:px-8">
        <a href="#top" aria-label="IronLog home">
          <Logo />
        </a>

        <div className="hidden items-center gap-8 md:flex">
          {NAV_LINKS.map((link) => (
            <a
              key={link.href}
              href={link.href}
              className="text-sm font-medium text-muted transition-colors hover:text-fg"
            >
              {link.label}
            </a>
          ))}
        </div>

        <div className="flex items-center gap-2.5">
          <a
            href={SITE.github}
            target="_blank"
            rel="noreferrer"
            className="hidden size-9 place-items-center rounded-lg text-muted ring-1 ring-line transition-colors hover:text-fg hover:ring-white/20 sm:grid"
            aria-label="IronLog on GitHub"
          >
            <GithubIcon className="size-4" />
          </a>
          <a
            href="#get"
            className="rounded-lg bg-lime px-4 py-2 text-sm font-semibold text-ink transition-transform hover:scale-[1.03] active:scale-95"
          >
            Get IronLog
          </a>
        </div>
      </nav>
    </header>
  );
}
