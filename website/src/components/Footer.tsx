import { GithubIcon } from "./Icons";
import { Logo } from "./Logo";
import { NAV_LINKS, SITE } from "@/lib/site";

export function Footer() {
  return (
    <footer className="border-t border-line">
      <div className="mx-auto flex max-w-6xl flex-col items-center justify-between gap-6 px-5 py-10 sm:flex-row sm:px-8">
        <div className="flex flex-col items-center gap-3 sm:items-start">
          <Logo />
          <p className="text-sm text-muted-2">
            Track your gains. Own your progress.
          </p>
        </div>

        <nav className="flex flex-wrap items-center justify-center gap-x-6 gap-y-2">
          {NAV_LINKS.map((link) => (
            <a
              key={link.href}
              href={link.href}
              className="text-sm text-muted transition-colors hover:text-fg"
            >
              {link.label}
            </a>
          ))}
          <a
            href={SITE.github}
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center gap-1.5 text-sm text-muted transition-colors hover:text-fg"
          >
            <GithubIcon className="size-4" />
            GitHub
          </a>
        </nav>
      </div>
      <div className="border-t border-line/60 py-5 text-center text-xs text-muted-2">
        © {new Date().getFullYear()} IronLog · A personal gym tracker · Not
        affiliated with Apple Inc.
      </div>
    </footer>
  );
}
