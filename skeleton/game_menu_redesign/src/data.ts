export type MenuItem = {
  label: string;
  description: string;
  disabled?: boolean;
};

export const MENU_ITEMS: MenuItem[] = [
  { label: "Items", description: "Use items." },
  { label: "Equip", description: "Change equipment." },
  { label: "Palette", description: "Set the action palette." },
  { label: "Mags", description: "Check on your MAG." },
  { label: "Quest", description: "Cannot be used here.", disabled: true },
  { label: "System", description: "Change system settings." },
];

export type StatRow = {
  label: string;
  value: string;
  /** Lv-style row: value follows the label instead of right-aligning */
  inline?: boolean;
  /** Numeric values use wider tracking like the original */
  numeric?: boolean;
};

export const STAT_PAGES: StatRow[][] = [
  [
    { label: "Lv", value: "60", inline: true, numeric: true },
    { label: "Type", value: "HUcast" },
    { label: "Exp Pts", value: "567644", numeric: true },
    { label: "To Next Lv", value: "21986", numeric: true },
    { label: "Meseta", value: "56558", numeric: true },
  ],
  [
    { label: "HP", value: "780", numeric: true },
    { label: "TP", value: "0", numeric: true },
    { label: "ATP", value: "1180", numeric: true },
    { label: "DFP", value: "512", numeric: true },
    { label: "MST", value: "0", numeric: true },
  ],
  [
    { label: "ATA", value: "195", numeric: true },
    { label: "EVP", value: "480", numeric: true },
    { label: "LCK", value: "40", numeric: true },
    { label: "Section ID", value: "Redria" },
    { label: "Guild Card", value: "41228317", numeric: true },
  ],
  [
    { label: "Play Time", value: "128:45:12", numeric: true },
    { label: "Deaths", value: "37", numeric: true },
    { label: "Quests Cleared", value: "64", numeric: true },
    { label: "Kills", value: "15204", numeric: true },
    { label: "Ship", value: "Ragol" },
  ],
];
