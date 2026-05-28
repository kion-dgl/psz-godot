import { useState } from 'react';
import { ALL_CLASSES } from './classData';
import SlatsView from './SlatsView';
import { PSZ_SLATS_PALETTE } from './slatsPalettes';

export default function CharacterSelect() {
  const [selectedId, setSelectedId] = useState('humar');

  return (
    <div style={{ width: 960, height: 540, overflow: 'hidden' }}>
      <SlatsView
        classes={ALL_CLASSES}
        selectedId={selectedId}
        onSelect={setSelectedId}
        palette={PSZ_SLATS_PALETTE}
      />
    </div>
  );
}
