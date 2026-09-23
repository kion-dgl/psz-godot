import Frame from "./Frame";

type Props = { text: string };

export default function DescriptionPanel({ text }: Props) {
  return (
    <section
      aria-label="Description"
      aria-live="polite"
      className="absolute anim-left"
      style={{ left: 32, top: 738, width: 455, height: 250, animationDelay: "160ms" }}
    >
      <Frame
        width={455}
        height={250}
        points="24,0 431,0 455,24 455,226 431,250 24,250 0,226 0,24"
        inner={[{ points: "28,12 427,12 443,28 443,222 427,238 28,238 12,222 12,28" }]}
      />
      <p
        key={text}
        className="absolute pixel-text stage-text anim-swap select-none m-0"
        style={{ left: 36, top: 44, right: 30, fontSize: 48, color: "#121212", letterSpacing: "0.01em" }}
      >
        {text}
      </p>
    </section>
  );
}
