import Link from "next/link";

export default function HomePage() {
  return (
    <main>
      <section className="hero">
        <div className="hero-copy">
          <p className="eyebrow">Votre studio. Votre signal. Votre son.</p>
          <h1>Branchez l’impossible.</h1>
          <p className="hero-lead">
            Explorez amplis, pédales et câblages dans un studio 3D pensé comme un véritable espace de création sonore.
          </p>
          <div className="hero-actions">
            <Link className="button primary" href="/signup">Créer mon espace</Link>
            <a className="button secondary" href="#features">Découvrir le studio</a>
          </div>
          <p className="microcopy">Compte gratuit · Aucun moyen de paiement requis</p>
        </div>
        <div className="amp-stage" aria-label="Illustration abstraite d’un amplificateur">
          <div className="glow glow-one" />
          <div className="glow glow-two" />
          <div className="amp">
            <div className="amp-top">
              <span className="pilot-light" />
              {["Gain", "Tone", "Level", "Air"].map((label, index) => (
                <span className="knob-wrap" key={label}>
                  <span className={`knob knob-${index + 1}`} />
                  <span>{label}</span>
                </span>
              ))}
            </div>
            <div className="amp-cloth"><span className="amp-sign">robine</span></div>
          </div>
          <div className="pedal pedal-a"><i /><span>EMBER</span></div>
          <div className="pedal pedal-b"><i /><span>TIDELINE</span></div>
          <svg className="cable" viewBox="0 0 620 250" aria-hidden="true">
            <path d="M32 203 C120 290, 203 121, 294 211 S465 270, 585 159" />
          </svg>
        </div>
      </section>

      <section className="manifesto" id="features">
        <p className="section-label">Un instrument avant d’être un logiciel</p>
        <h2>Le chemin du signal devient un terrain de jeu.</h2>
        <div className="feature-grid">
          <article><span>01</span><h3>Construisez</h3><p>Disposez votre rig librement, du premier câble au dernier haut-parleur.</p></article>
          <article><span>02</span><h3>Écoutez</h3><p>Chaque geste reste musical, immédiat et fidèle à votre intention.</p></article>
          <article><span>03</span><h3>Retrouvez</h3><p>Votre compte garde vos espaces et vos idées prêts pour la prochaine session.</p></article>
        </div>
      </section>

      <section className="closing-cta">
        <p className="eyebrow">Le silence attend.</p>
        <h2>Allumez votre studio.</h2>
        <Link className="button light" href="/signup">Commencer maintenant</Link>
      </section>
    </main>
  );
}
