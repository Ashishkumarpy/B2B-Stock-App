import { useState } from 'react';
import { Link } from 'react-router';
import { motion } from 'motion/react';
import { ShoppingCart, Eye, Heart, Star, Check } from 'lucide-react';
import { useCart } from '../context/CartContext';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from './ui/dialog';
import type { Product } from '../../lib/productService';

const FALLBACK_IMAGE = 'https://images.unsplash.com/photo-1561172472-4f2d94f35e87?w=600';

/**
 * Stable pseudo-rating derived from the product id, so the same product always
 * shows the same value. Placeholder until real review data exists.
 */
function ratingFor(id: string): number {
  let hash = 0;
  for (let i = 0; i < id.length; i++) hash = (hash * 31 + id.charCodeAt(i)) >>> 0;
  return 4 + (hash % 10) / 10; // 4.0 – 4.9
}

function isNew(createdAt?: string): boolean {
  if (!createdAt) return false;
  const created = new Date(createdAt).getTime();
  if (Number.isNaN(created)) return false;
  const THIRTY_DAYS = 30 * 24 * 60 * 60 * 1000;
  return Date.now() - created < THIRTY_DAYS;
}

interface ProductCardProps {
  product: Product;
  index?: number;
  /** Force a corner badge (e.g. "Hot") regardless of the auto badges. */
  badge?: string;
  /** Visual tone — use "dark" on dark-background sections. */
  tone?: 'light' | 'dark';
}

export function ProductCard({ product, index = 0, badge, tone = 'light' }: ProductCardProps) {
  const { addItem } = useCart();
  const [wishlisted, setWishlisted] = useState(false);
  const [added, setAdded] = useState(false);

  const dark = tone === 'dark';
  const image = product.imageUrl || FALLBACK_IMAGE;
  const outOfStock = product.stockStatus === 'out_of_stock';
  const lowStock = product.stockStatus === 'low_stock';
  const moq = product.threshold && product.threshold > 0 ? product.threshold : 1;
  const rating = ratingFor(product.id);
  const cornerBadge = badge ?? (isNew(product.createdAt) ? 'New' : null);

  const c = {
    imageWrap: dark ? 'bg-slate-800 border-white/15' : 'bg-white border-slate-200',
    category: dark ? 'text-white/60' : 'text-slate-500',
    name: dark ? 'text-white' : 'text-slate-900',
    ratingNum: dark ? 'text-white/50' : 'text-slate-400',
    emptyStar: dark ? 'text-white/20' : 'text-slate-300',
    price: dark ? 'text-white' : 'text-slate-900',
    moq: dark ? 'text-white/50' : 'text-slate-400',
  };

  const handleAddToCart = (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    if (outOfStock) return;
    addItem({ id: product.id, name: product.name, price: product.price, image, quantity: moq, moq });
    setAdded(true);
    setTimeout(() => setAdded(false), 1500);
  };

  const toggleWishlist = (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setWishlisted((w) => !w);
  };

  return (
    <motion.div
      className="group relative"
      initial={{ opacity: 0, y: 24 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: '-40px' }}
      transition={{ duration: 0.5, delay: index * 0.04, ease: [0.22, 1, 0.36, 1] }}
    >
      <Link to={`/product/${product.id}`} className="block">
        {/* Image */}
        <div className={`aspect-square overflow-hidden mb-4 relative border ${c.imageWrap} group-hover:border-brand/40 group-hover:shadow-[0_12px_40px_rgb(0,0,0,0.10)] transition-all duration-300`}>
          <img
            src={image}
            alt={product.name}
            loading="lazy"
            className="w-full h-full object-contain p-5 group-hover:scale-105 transition-transform duration-500"
          />

          {/* Corner badges */}
          <div className="absolute top-3 left-3 flex flex-col gap-1.5">
            {cornerBadge && (
              <span className="px-2.5 py-1 bg-brand text-white text-[10px] uppercase tracking-widest font-medium">
                {cornerBadge}
              </span>
            )}
            {lowStock && !outOfStock && (
              <span className="px-2.5 py-1 bg-amber-500 text-white text-[10px] uppercase tracking-widest font-medium">
                Low Stock
              </span>
            )}
          </div>

          {/* Wishlist */}
          <button
            type="button"
            onClick={toggleWishlist}
            aria-label="Add to wishlist"
            className="absolute top-3 right-3 w-9 h-9 bg-white/90 backdrop-blur border border-slate-200 flex items-center justify-center opacity-0 group-hover:opacity-100 translate-y-1 group-hover:translate-y-0 transition-all duration-300 hover:border-brand"
          >
            <Heart className={`w-4 h-4 ${wishlisted ? 'fill-brand text-brand' : 'text-slate-700'}`} />
          </button>

          {/* Out of stock overlay */}
          {outOfStock && (
            <div className="absolute inset-0 bg-white/70 flex items-center justify-center">
              <span className="text-xs uppercase tracking-widest text-slate-900 border border-slate-900 px-4 py-2">
                Out of Stock
              </span>
            </div>
          )}

          {/* Hover action bar */}
          {!outOfStock && (
            <div className="absolute inset-x-0 bottom-0 flex translate-y-full group-hover:translate-y-0 transition-transform duration-300">
              <button
                type="button"
                onClick={handleAddToCart}
                className="flex-1 h-11 bg-slate-900 text-white text-[11px] uppercase tracking-widest flex items-center justify-center gap-2 hover:bg-brand transition-colors"
              >
                {added ? (
                  <>
                    <Check className="w-4 h-4" /> Added
                  </>
                ) : (
                  <>
                    <ShoppingCart className="w-4 h-4" /> Add
                  </>
                )}
              </button>
              <QuickView product={product} image={image} rating={rating} moq={moq} onAdd={handleAddToCart} />
            </div>
          )}
        </div>
      </Link>

      {/* Meta */}
      <Link to={`/product/${product.id}`} className="block">
        <div className={`text-[10px] uppercase tracking-widest mb-1 ${c.category}`}>{product.category}</div>
        <h3 className={`text-sm tracking-wide mb-1.5 line-clamp-1 group-hover:text-brand transition-colors ${c.name}`}>
          {product.name}
        </h3>
        <div className="flex items-center gap-1 mb-1.5">
          {[0, 1, 2, 3, 4].map((i) => (
            <Star
              key={i}
              className={`w-3 h-3 ${i < Math.round(rating) ? 'fill-brand text-brand' : c.emptyStar}`}
            />
          ))}
          <span className={`text-[10px] ml-1 ${c.ratingNum}`}>{rating.toFixed(1)}</span>
        </div>
        <div className="flex items-baseline gap-2">
          <span className={`text-base tracking-wide ${c.price}`}>₹{product.price.toLocaleString()}</span>
          <span className={`text-[10px] uppercase tracking-wider ${c.moq}`}>MOQ {moq}</span>
        </div>
      </Link>
    </motion.div>
  );
}

interface QuickViewProps {
  product: Product;
  image: string;
  rating: number;
  moq: number;
  onAdd: (e: React.MouseEvent) => void;
}

function QuickView({ product, image, rating, moq, onAdd }: QuickViewProps) {
  return (
    <Dialog>
      <DialogTrigger asChild>
        <button
          type="button"
          onClick={(e) => {
            e.preventDefault();
            e.stopPropagation();
          }}
          aria-label="Quick view"
          className="w-11 h-11 bg-white text-slate-900 flex items-center justify-center border-l border-slate-200 hover:bg-slate-100 transition-colors"
        >
          <Eye className="w-4 h-4" />
        </button>
      </DialogTrigger>
      <DialogContent className="max-w-3xl p-0 overflow-hidden">
        <div className="grid md:grid-cols-2">
          <div className="aspect-square bg-slate-50 border-r border-slate-200 flex items-center justify-center p-8">
            <img src={image} alt={product.name} className="max-w-full max-h-full object-contain" />
          </div>
          <div className="p-8 flex flex-col">
            <DialogHeader className="text-left space-y-0">
              <div className="text-[10px] uppercase tracking-widest text-brand mb-2">{product.category}</div>
              <DialogTitle className="text-xl tracking-wide normal-case">{product.name}</DialogTitle>
            </DialogHeader>
            <div className="flex items-center gap-1 my-3">
              {[0, 1, 2, 3, 4].map((i) => (
                <Star
                  key={i}
                  className={`w-3.5 h-3.5 ${i < Math.round(rating) ? 'fill-brand text-brand' : 'text-slate-300'}`}
                />
              ))}
              <span className="text-xs text-slate-400 ml-1">{rating.toFixed(1)}</span>
            </div>
            <div className="text-2xl tracking-wide mb-4">₹{product.price.toLocaleString()}</div>
            {product.description && (
              <p className="text-sm text-slate-600 leading-relaxed mb-4 line-clamp-4">{product.description}</p>
            )}
            <div className="text-xs uppercase tracking-wider text-slate-500 mb-6">
              SKU {product.code} · MOQ {moq}
            </div>
            <div className="mt-auto flex gap-3">
              <button
                type="button"
                onClick={onAdd}
                className="flex-1 h-12 bg-slate-900 text-white text-xs uppercase tracking-widest flex items-center justify-center gap-2 hover:bg-brand transition-colors"
              >
                <ShoppingCart className="w-4 h-4" /> Add to Cart
              </button>
              <Link
                to={`/product/${product.id}`}
                className="h-12 px-6 border border-slate-300 text-xs uppercase tracking-widest flex items-center justify-center hover:border-slate-900 transition-colors"
              >
                Details
              </Link>
            </div>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
