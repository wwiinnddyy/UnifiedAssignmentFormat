export interface UafAssignment {
  subject: string;
  date: string;
  content: string;
  tags: string[];
}

export type UafDocument = [UafAssignment, ...UafAssignment[]];
