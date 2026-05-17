export type StockStatus = 'in_stock' | 'low_stock' | 'out_of_stock';

export interface ProductImage {
  url: string;
  publicId: string;   // Cloudinary public_id (used for deletion & transforms)
  /** @deprecated Use publicId. Kept for documents written before Cloudinary migration. */
  path?: string;
}

export interface Product {
  id: string;
  name: string;
  code: string;           // formerly SKU
  category: string;
  quantity: number;
  threshold: number;
  supplierId: string;
  price: number;
  costPrice?: number;
  imageUrl?: string;      // Main image URL (first in images[])
  /** @deprecated Use images[0].publicId */
  imagePath?: string;
  images?: ProductImage[];
  unit?: string;
  description?: string;
  stockStatus: StockStatus;
  updatedAt: string;      // ISO date string
  createdAt: string;
}

export interface Supplier {
  id: string;
  name: string;
  contactEmail?: string;
  contactPhone?: string;
}
