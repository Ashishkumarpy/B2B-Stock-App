export type TransactionType = 'stock_in' | 'stock_out' | 'adjustment';

export interface Transaction {
  id: string;
  productId: string;
  productName: string;
  type: TransactionType;
  quantity: number;
  workerId: string;
  workerName: string;
  notes?: string;
  createdAt: string; // ISO date string
}
