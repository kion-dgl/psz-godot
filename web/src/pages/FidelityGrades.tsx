import { siteUrl } from '../../../spec/src/utils/site';
import baseline from '../../../spec/src/data/fidelity-grades.json';
import './FidelityGrades.css';
import { scorecardIssuesUrl } from '../../../spec/src/utils/scorecard';

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
        {baseline.areas.map(({ area, grade, assessment, next, label }) => (
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
            <p><a href={scorecardIssuesUrl(label)} aria-label={`Open issues for ${area}`}>Open issues ↗</a></p>
          </article>
        ))}
      </div>
      <footer>
        <a href={siteUrl('/fidelity/')}>Grading criteria & evidence ↗</a>
      </footer>
    </section>
  );
}
