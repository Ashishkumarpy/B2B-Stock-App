export type UserRole = 'admin' | 'manager' | 'worker' | 'customer';

export interface AppUser {
  id: string;
  name: string;
  email: string;
  role: UserRole;
  createdAt: string; // ISO date string
}
