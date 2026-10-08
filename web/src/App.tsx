import { Routes, Route } from 'react-router-dom';
import { Suspense, lazy } from 'react';
import SiteNav from './SiteNav';
import Landing from './pages/Landing';

const QuestHome = lazy(() => import('./quest-editor/QuestHome'));
const QuestEditor = lazy(() => import('./quest-editor/QuestEditor'));
const StorybookViewer = lazy(() => import('./storybook/StorybookViewer'));
const EnemyGallery = lazy(() => import('./storybook/EnemyGallery'));
const WeaponGallery = lazy(() => import('./storybook/WeaponGallery'));
const PlayerAnimationStorybook = lazy(() => import('./storybook/PlayerAnimationStorybook'));
const FlapLab = lazy(() => import('./storybook/FlapLab'));
const LightingLab = lazy(() => import('./storybook/LightingLab'));
const StageEditor = lazy(() => import('./stage-editor/UnifiedStageEditor'));
const FloorMeshEditor = lazy(() => import('./floor-mesh-editor/FloorMeshEditor'));
const FloorColliderBuilder = lazy(() => import('./floor-collider-builder/FloorColliderBuilder'));
const CityWalkMock = lazy(() => import('./city-walk-mock/CityWalkMock'));
const TeleporterMock = lazy(() => import('./teleporter-mock/TeleporterMock'));
const SvgCheck = lazy(() => import('./svg-check/SvgCheck'));
const OfficeEditor = lazy(() => import('./office-editor/OfficeEditor'));
const MarketEditor = lazy(() => import('./market-editor/MarketEditor'));
const CityLab = lazy(() => import('./city-lab/CityLab'));
const ShrinePillarLab = lazy(() => import('./shrine-lab/ShrinePillarLab'));
const RetargetViewer = lazy(() => import('./retarget/RetargetViewer'));
const RetargetTuner = lazy(() => import('./retarget/RetargetTuner'));
const RetargetTunerVrm = lazy(() => import('./retarget/RetargetTunerVrm'));
const MixamoLoader = lazy(() => import('./retarget/MixamoLoader'));
const BakedVrmaPszViewer = lazy(() => import('./retarget/BakedVrmaPszViewer'));
const PsoIkVrmViewer = lazy(() => import('./retarget/PsoIkVrmViewer'));
const BasicWeaponPreview = lazy(() => import('./storybook/BasicWeaponPreview'));
const MenuDesign = lazy(() => import('./storybook/MenuDesign'));
const SettingsMockup = lazy(() => import('./settings/SettingsMockup'));
const CharacterCreator = lazy(() => import('./character-creator/CharacterCreator'));
const StartMenu = lazy(() => import('./start-menu/StartMenu'));
const ControlsDiagram = lazy(() => import('./controls/ControlsDiagram'));
const SfxLabeler = lazy(() => import('./sfx-labeler/SfxLabeler'));
const PhotoMode = lazy(() => import('./photo-mode/PhotoMode'));
const TitleScreen = lazy(() => import('./title-screen/TitleScreen'));
const DodgeDebug = lazy(() => import('./dodge-debug/DodgeDebug'));
const ComboDebug = lazy(() => import('./combo-debug/ComboDebug'));
const CombatRoom = lazy(() => import('./combat-room/CombatRoom'));
const CompanionRoom = lazy(() => import('./companion-room/CompanionRoom'));
const TechRoom = lazy(() => import('./tech-room/TechRoom'));
const PhotonRoom = lazy(() => import('./photon-room/PhotonRoom'));
const EnemyRoom = lazy(() => import('./enemy-room/EnemyRoom'));
const EnemyRoomIndex = lazy(() => import('./enemy-room/EnemyRoomIndex'));
const BossRoom = lazy(() => import('./boss-room/BossRoom'));
const BossRoomIndex = lazy(() => import('./boss-room/BossRoomIndex'));
const TextureAnimEditor = lazy(() => import('./texture-anim/TextureAnimEditor'));
const AssetLoader = lazy(() => import('./asset-loader/AssetLoader'));
const CharacterSelect = lazy(() => import('./character-select/CharacterSelect'));
const UndergroundEditor = lazy(() => import('./underground-editor/UndergroundEditor'));
const PaletteEditor = lazy(() => import('./palette-editor/PaletteEditorMockup'));
const ShopIndex = lazy(() => import('./shop-3d/ShopIndex'));
const WallDebug = lazy(() => import('./wall-debug/WallDebug'));
const FieldGenerator = lazy(() => import('./field-generator/FieldGenerator'));
const FieldSolver = lazy(() => import('./field-solver/FieldSolver'));
const ShopMenu3D = lazy(() => import('./shop-3d/ShopMenu3D'));

export default function App() {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100vh' }}>
      <SiteNav />
      <div style={{ flex: 1, overflow: 'hidden' }}>
        <Suspense fallback={<div style={{ padding: 32, color: '#888' }}>Loading...</div>}>
          <Routes>
            <Route path="/" element={<Landing />} />
            <Route path="/quest-editor" element={<QuestHome />} />
            <Route path="/quest-editor/edit" element={<QuestEditor />} />
            <Route path="/storybook" element={<StorybookViewer />} />
            <Route path="/storybook/enemies" element={<EnemyGallery />} />
            <Route path="/storybook/weapons" element={<WeaponGallery />} />
            <Route path="/storybook/basic-weapons" element={<BasicWeaponPreview />} />
            <Route path="/storybook/player-animations" element={<PlayerAnimationStorybook />} />
            <Route path="/storybook/flap-lab" element={<FlapLab />} />
            <Route path="/storybook/lighting-lab" element={<LightingLab />} />
            <Route path="/stage-editor" element={<StageEditor />} />
            <Route path="/floor-mesh-editor" element={<FloorMeshEditor />} />
            <Route path="/floor-collider-builder" element={<FloorColliderBuilder />} />
            <Route path="/city-walk-mock" element={<CityWalkMock />} />
            <Route path="/teleporter-mock" element={<TeleporterMock />} />
            <Route path="/svg-check" element={<SvgCheck />} />
            <Route path="/office-editor" element={<OfficeEditor />} />
            <Route path="/market-editor" element={<MarketEditor />} />
            <Route path="/city-lab" element={<CityLab />} />
            <Route path="/shrine-pillar-lab" element={<ShrinePillarLab />} />
            <Route path="/menu-design" element={<MenuDesign />} />
            <Route path="/settings" element={<SettingsMockup />} />
            <Route path="/retarget" element={<RetargetViewer />} />
            <Route path="/retarget-tuner" element={<RetargetTuner />} />
            <Route path="/retarget-tuner-vrm" element={<RetargetTunerVrm />} />
            <Route path="/vrm-mixamo" element={<MixamoLoader />} />
            <Route path="/vrma-to-psz" element={<BakedVrmaPszViewer />} />
            <Route path="/pso-ik-vrm" element={<PsoIkVrmViewer />} />
            <Route path="/character-creator" element={<CharacterCreator />} />
            <Route path="/start-menu" element={<StartMenu />} />
            <Route path="/controls" element={<ControlsDiagram />} />
            <Route path="/sfx-labeler" element={<SfxLabeler />} />
            <Route path="/photo-mode" element={<PhotoMode />} />
            <Route path="/title-screen" element={<TitleScreen />} />
            <Route path="/asset-loader" element={<AssetLoader />} />
            <Route path="/character-select" element={<CharacterSelect />} />
            <Route path="/underground-editor" element={<UndergroundEditor />} />
            <Route path="/dodge-debug" element={<DodgeDebug />} />
            <Route path="/combo-debug" element={<ComboDebug />} />
            <Route path="/combat-room" element={<CombatRoom />} />
            <Route path="/companion-room" element={<CompanionRoom />} />
            <Route path="/tech-room" element={<TechRoom />} />
            <Route path="/photon-room" element={<PhotonRoom />} />
            <Route path="/enemy-room" element={<EnemyRoomIndex />} />
            <Route path="/enemy-room/:archetype" element={<EnemyRoom />} />
            <Route path="/boss-room" element={<BossRoomIndex />} />
            <Route path="/boss-room/:bossId" element={<BossRoom />} />
            <Route path="/texture-anim" element={<TextureAnimEditor />} />
            <Route path="/palette-editor" element={<PaletteEditor />} />
            <Route path="/shop-3d" element={<ShopIndex />} />
            <Route path="/shop-3d/:shopId" element={<ShopMenu3D />} />
            <Route path="/wall-debug" element={<WallDebug />} />
            <Route path="/field-generator" element={<FieldGenerator />} />
            <Route path="/field-solver" element={<FieldSolver />} />
          </Routes>
        </Suspense>
      </div>
    </div>
  );
}
