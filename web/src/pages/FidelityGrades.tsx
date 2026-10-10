import { siteUrl } from '../../../spec/src/utils/site';
import baseline from '../../../spec/src/data/fidelity-grades.json';
import './FidelityGrades.css';
import { scorecardIssuesUrl, gradeRank, gradeBarWidth } from '../../../spec/src/utils/scorecard';

export default function FidelityGrades({ showCriteriaLink = true }: { showCriteriaLink?: boolean }) {
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
      <p className="fidelity-note">Overall is an editorial assessment, not an average or a measured fidelity percentage. Grades improve through playtesting; passing automated checks alone does not raise them. Bars show the letter-grade scale, not percent complete.</p>
      <div className="fidelity-grid">
        {[...baseline.areas].sort((a, b) => gradeRank(b.grade) - gradeRank(a.grade)).map(({ area, grade, assessment, next, label, reviewed_on }) => (
          <article className="fidelity-card" key={area}>
            <div className="fidelity-card-heading">
              <h3><a href={scorecardIssuesUrl(label)} aria-label={`Open issues for ${area}`}>{area} ↗</a></h3>
              <strong className="fidelity-grade" data-grade={grade[0]} aria-label={`Grade ${grade}`}>{grade}</strong>
            </div>
            <div className="fidelity-bar" aria-hidden="true"><span data-grade={grade[0]} style={{ width: `${gradeBarWidth(grade)}%` }} /></div>
            <p>{assessment}</p>
            {reviewed_on && <p className="fidelity-note">Reviewed {reviewed_on}.</p>}
            <details>
              <summary>Next review target</summary>
              <p>{next}</p>
            </details>
          </article>
        ))}
      </div>
      {showCriteriaLink && <footer>
        <a href={siteUrl('/fidelity/')}>Grading criteria & evidence ↗</a>
      </footer>}
    </section>
  );
}
