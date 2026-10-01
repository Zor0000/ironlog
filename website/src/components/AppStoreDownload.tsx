import { SITE } from "@/lib/site";
import { AppleIcon } from "./Icons";

export function AppStoreDownload({ className = "" }: { className?: string }) {
  const content = <><AppleIcon className="size-5 shrink-0" />Download on the App Store</>;
  const classes = `inline-flex items-center justify-center gap-2 rounded-xl bg-lime px-6 py-3.5 text-base font-semibold text-ink ${className}`;

  return SITE.appStoreUrl ? (
    <a href={SITE.appStoreUrl} className={classes}>{content}</a>
  ) : (
    <button type="button" disabled title="Coming soon to the App Store" aria-label="Download on the App Store — coming soon" className={`${classes} cursor-not-allowed opacity-60`}>
      {content}
    </button>
  );
}
