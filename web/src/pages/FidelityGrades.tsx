import baseline from '../../../data/fidelity_grades.json';
import './FidelityGrades.css';

export default function FidelityGrades() {
  return (
    <section className="fidelity-grades" aria-labelledby="fidelity-heading">
      <header className="fidelity-header">
        <div>
          <p className="fidelity-eyebrow">Project report card · {baseline.assessed_on}</p>
          <h2 id="fidelity-heading">Fidelity & quality</h2>
          <p>Kion’s playtest grades across presentation, gameplay and completeness.</p>
        </div>
        <div className="fidelity-overall">
          <strong>{baseline.overall.grade}</strong>
          <span>Provisional overall</span>
        </div>
      </header>
      <p className="fidelity-note">Overall is an editorial assessment, not an average or a measured fidelity percentage. Grades improve through playtesting; passing automated checks alone does not raise them.</p>
      <div className="fidelity-grid">
        {baseline.areas.map(({ area, grade, assessment, next }) => (
          <article className="fidelity-card" key={area}>
            <div className="fidelity-card-heading">
              <h3>{area}</h3>
              <strong className="fidelity-grade" data-grade={grade[0]} aria-label={`Grade ${grade}`}>{grade}</strong>
            </div>
            <p>{assessment}</p>
            <details>
              <summary>Next review target</summary>
              <p>{next}</p>
            </details>
          </article>
        ))}
      </div>
      <footer>
        <a href="https://github.com/kion-dgl/psz-godot/issues/682">Combat fidelity roadmap ↗</a>
        <a href="https://psz.onl/fidelity/">Grading criteria & evidence ↗</a>
      </footer>
    </section>
  );
}
