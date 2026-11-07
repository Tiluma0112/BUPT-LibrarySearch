export interface ReaderProfile {
  name: string;
  studentId: string;
  avatarUrl: string;
  avatarLocalUri: string;
}

export interface CurrentLoan {
  id: string;
  title: string;
  barcode: string;
  callNumber: string;
  department: string;
  status: string;
  dueDate: string;
  overdue: boolean;
}

export interface BorrowHistory {
  id: string;
  title: string;
  isbn: string;
  authors: string;
  publication: string;
  status: string;
  latestAt: string;
  cycles: BorrowCycle[];
  otherEvents: string[];
}

export interface BorrowCycle {
  id: string;
  barcode: string;
  borrowedAt: string;
  returnedAt: string;
  renewalCount: number;
  status: string;
}

export interface PersonalLibrarySnapshot {
  currentLoans: CurrentLoan[];
  history: BorrowHistory[];
}
