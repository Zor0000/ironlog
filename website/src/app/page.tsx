import { Nav } from "@/components/Nav";
import { Hero } from "@/components/Hero";
import { Showcase } from "@/components/Showcase";
import { Features } from "@/components/Features";
import { LiveActivity } from "@/components/LiveActivity";
import { Why } from "@/components/Why";
import { CTA } from "@/components/CTA";
import { Footer } from "@/components/Footer";

export default function Home() {
  return (
    <>
      <Nav />
      <main>
        <Hero />
        <Showcase />
        <Features />
        <LiveActivity />
        <Why />
        <CTA />
      </main>
      <Footer />
    </>
  );
}
