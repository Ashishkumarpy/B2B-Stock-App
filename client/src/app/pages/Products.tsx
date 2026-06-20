import { useState, useEffect, useMemo } from 'react';
import { motion } from 'motion/react';
import { Link, useSearchParams } from 'react-router';
import { ArrowRight, Loader2 } from 'lucide-react';
import { subscribeToProducts, type Product } from '../../lib/productService';
import { ProductCard } from '../components/ProductCard';

export default function Products() {
  const [products, setProducts] = useState<Product[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const unsub = subscribeToProducts((data) => {
      setProducts(data);
      setLoading(false);
    });
    return () => unsub();
  }, []);

  const [searchParams] = useSearchParams();
  const searchBarQuery = searchParams.get('search') || '';

  const inStockProducts = useMemo(() => {
    if (searchBarQuery) {
      const q = searchBarQuery.toLowerCase().trim();
      return products.filter(
        (p) =>
          p.name.toLowerCase().includes(q) ||
          p.code.toLowerCase().includes(q) ||
          (p.category && p.category.toLowerCase().includes(q)) ||
          (p.description && p.description.toLowerCase().includes(q))
      );
    }
    return products.filter((p) => p.stockStatus !== 'out_of_stock');
  }, [products, searchBarQuery]);

  const categories = useMemo(() => {
    return Array.from(new Set(products.map((p) => p.category)));
  }, [products]);

  return (
    <div className="min-h-screen bg-white text-slate-900 pt-36">
      {/* Hero Section */}
      <section className="py-16 border-b border-slate-200">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.8 }}>
            <h1 className="text-6xl md:text-8xl tracking-tighter uppercase mb-6">ALL PRODUCTS</h1>
            <p className="text-lg text-slate-600 uppercase tracking-wider max-w-2xl">
              Explore our complete range of premium corporate gifting solutions
            </p>
          </motion.div>
        </div>
      </section>

      {/* Shop by Category */}
      {!loading && categories.length > 0 && (
        <section className="py-24">
          <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
            <div className="mb-16">
              <h2 className="text-4xl md:text-5xl tracking-tighter uppercase mb-4">SHOP BY CATEGORY</h2>
            </div>
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              {categories.map((cat, index) => {
                const count = products.filter((p) => p.category === cat).length;
                return (
                  <Link key={cat} to={`/category/${encodeURIComponent(cat)}`}>
                    <motion.div
                      className="group relative bg-white hover:bg-slate-50 border border-slate-200 hover:border-slate-300 p-10 transition-all duration-300 cursor-pointer"
                      initial={{ opacity: 0, y: 20 }}
                      whileInView={{ opacity: 1, y: 0 }}
                      viewport={{ once: true }}
                      transition={{ delay: index * 0.05 }}
                    >
                      <h3 className="text-2xl uppercase tracking-wider mb-2">{cat}</h3>
                      <p className="text-sm text-slate-600 uppercase tracking-wider mb-6">{count} Products</p>
                      <div className="flex items-center gap-2 text-sm uppercase tracking-wider group-hover:gap-3 transition-all">
                        View All <ArrowRight className="w-4 h-4" />
                      </div>
                    </motion.div>
                  </Link>
                );
              })}
            </div>
          </div>
        </section>
      )}

      {/* All Products Grid */}
      <section className="py-24 bg-white text-slate-900">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="mb-16">
            <h2 className="text-4xl md:text-5xl tracking-tighter uppercase mb-4">
              {searchBarQuery ? `Search Results for "${searchBarQuery}"` : 'FEATURED PRODUCTS'}
            </h2>
            <p className="text-lg text-slate-600 uppercase tracking-wider">
              {searchBarQuery ? `Found ${inStockProducts.length} matching items` : 'Handpicked bestsellers'}
            </p>
            {searchBarQuery && (
              <Link
                to="/products"
                className="inline-block mt-4 text-xs uppercase tracking-widest text-slate-500 hover:text-slate-900 underline"
              >
                Clear Search
              </Link>
            )}
          </div>

          {loading ? (
            <div className="flex items-center justify-center py-24">
              <Loader2 className="w-8 h-8 animate-spin text-slate-500" />
            </div>
          ) : inStockProducts.length === 0 ? (
            <div className="text-center py-24">
              <p className="text-slate-500 uppercase tracking-widest text-sm">No products found. Add some from the admin panel.</p>
            </div>
          ) : (
            <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-6">
              {inStockProducts.map((product, index) => (
                <ProductCard key={product.id} product={product} index={index} />
              ))}
            </div>
          )}

          <div className="mt-12 text-center">
            <Link
              to="/#contact"
              className="inline-flex items-center gap-2 px-12 py-4 bg-slate-900 text-white hover:bg-slate-800 transition-colors uppercase tracking-wider text-sm"
            >
              Request Bulk Quote <ArrowRight className="w-4 h-4" />
            </Link>
          </div>
        </div>
      </section>
    </div>
  );
}
