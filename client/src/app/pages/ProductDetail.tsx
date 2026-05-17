import { useState, useEffect } from 'react';
import { useParams, Link } from 'react-router';
import { useCart } from '../context/CartContext';
import { motion } from 'motion/react';
import { ArrowRight, ChevronLeft, ShieldCheck, Truck, Clock, X, Loader2 } from 'lucide-react';
import { getProduct, type Product } from '../../lib/productService';

export default function ProductDetail() {
  const { id } = useParams();
  const { addItem } = useCart();

  const [product, setProduct] = useState<Product | null>(null);
  const [loading, setLoading] = useState(true);
  const [activeImage, setActiveImage] = useState<string | null>(null);
  const [quantity, setQuantity] = useState(50);
  const [isQuoteModalOpen, setIsQuoteModalOpen] = useState(false);

  useEffect(() => {
    if (!id) return;
    setLoading(true);
    getProduct(id).then((p) => {
      setProduct(p);
      if (p) {
        setQuantity(p.threshold || 50); // threshold = MOQ
        if (p.imageUrl) setActiveImage(p.imageUrl);
      }
      setLoading(false);
    });
  }, [id]);

  const handleQuantityChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const val = parseInt(e.target.value);
    setQuantity(isNaN(val) ? 0 : val);
  };

  const moq = product?.threshold || 50;

  const handleAddToCart = () => {
    if (!product) return;
    if (quantity < moq) {
      alert(`Minimum order quantity is ${moq}`);
      setQuantity(moq);
      return;
    }
    addItem({
      id: product.id,
      name: product.name,
      price: product.price,
      image: product.imageUrl || 'https://images.unsplash.com/photo-1561172472-4f2d94f35e87?w=600',
      quantity,
      moq,
    });
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-white text-slate-900 pt-36 flex items-center justify-center">
        <Loader2 className="w-8 h-8 animate-spin text-slate-500" />
      </div>
    );
  }

  if (!product) {
    return (
      <div className="min-h-screen bg-white text-slate-900 pt-36 flex flex-col items-center justify-center">
        <h1 className="text-4xl uppercase tracking-tighter mb-4">Product Not Found</h1>
        <Link to="/products" className="text-slate-600 hover:text-slate-900 uppercase tracking-widest text-sm underline">
          Back to Catalog
        </Link>
      </div>
    );
  }

  return (
    <div className="pt-32 bg-white min-h-screen text-slate-900">
      {/* Breadcrumb */}
      <div className="border-b border-slate-200 bg-white/95 backdrop-blur-sm">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4 flex items-center text-xs uppercase tracking-widest text-slate-600">
          <Link to="/" className="hover:text-slate-900 transition-colors">Home</Link>
          <span className="mx-2">/</span>
          <Link to="/products" className="hover:text-slate-900 transition-colors">Products</Link>
          <span className="mx-2">/</span>
          <span className="text-slate-900">{product.name}</span>
        </div>
      </div>

      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
        <Link to="/products" className="inline-flex items-center gap-2 text-xs uppercase tracking-widest text-slate-600 hover:text-slate-900 mb-8 transition-colors">
          <ChevronLeft className="w-4 h-4" /> Back to Catalog
        </Link>

        <div className="grid lg:grid-cols-2 gap-12 lg:gap-24">
          {/* Left: Product Gallery */}
          <motion.div
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            className="space-y-4"
          >
            {/* Main Image */}
            <div className="aspect-square bg-white/5 border border-white/10 overflow-hidden flex items-center justify-center p-8 relative group">
              <img
                src={activeImage || product.imageUrl || 'https://images.unsplash.com/photo-1561172472-4f2d94f35e87?w=800'}
                alt={product.name}
                className="max-w-full max-h-full object-contain transition-transform duration-700"
              />
            </div>

            {/* Thumbnails */}
            {product.images && product.images.length > 1 && (
              <div className="flex gap-4 overflow-x-auto pb-2 no-scrollbar">
                {product.images.map((img, idx) => (
                  <button
                    key={idx}
                    onClick={() => setActiveImage(img.url)}
                    className={`w-20 h-20 flex-shrink-0 border transition-all ${
                      activeImage === img.url ? 'border-white bg-white/10' : 'border-white/10 bg-white/5 hover:border-white/30'
                    }`}
                  >
                    <img src={img.url} alt={`Thumbnail ${idx}`} className="w-full h-full object-cover" />
                  </button>
                ))}
              </div>
            )}
          </motion.div>

          {/* Right: Product Details */}
          <motion.div
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            className="flex flex-col justify-center"
          >
            <div className="text-xs uppercase tracking-widest text-slate-500 mb-2">{product.category}</div>
            <h1 className="text-4xl md:text-5xl uppercase tracking-tighter mb-4 leading-tight">{product.name}</h1>
            <div className="text-2xl tracking-wider mb-2">₹{product.price.toLocaleString()} <span className="text-sm text-slate-500">/ unit</span></div>

            {/* Stock Status */}
            <div className="mb-6">
              {product.stockStatus === 'in_stock' && <span className="text-xs uppercase tracking-widest text-emerald-400">● In Stock ({product.quantity} units available)</span>}
              {product.stockStatus === 'low_stock' && <span className="text-xs uppercase tracking-widest text-yellow-400">● Low Stock ({product.quantity} units left)</span>}
              {product.stockStatus === 'out_of_stock' && <span className="text-xs uppercase tracking-widest text-red-400">● Out of Stock</span>}
            </div>

            {product.description && (
              <p className="text-slate-600 text-sm leading-relaxed mb-8">{product.description}</p>
            )}

            {/* Quantity and Actions */}
            <div className="mb-8">
              <label className="block text-xs uppercase tracking-widest mb-3 text-slate-600">
                Quantity (MOQ: {moq})
              </label>
              <div className="flex gap-4">
                <input
                  type="number"
                  value={quantity}
                  onChange={handleQuantityChange}
                  className="w-32 bg-white border border-slate-200 text-center text-lg focus:outline-none focus:border-slate-900 transition-colors py-4"
                  min={moq}
                  disabled={product.stockStatus === 'out_of_stock'}
                />
                <button
                  onClick={handleAddToCart}
                  disabled={product.stockStatus === 'out_of_stock'}
                  className="flex-1 bg-slate-900 text-white hover:bg-slate-800 transition-colors uppercase tracking-widest text-sm flex items-center justify-center gap-2 group disabled:opacity-40 disabled:cursor-not-allowed"
                >
                  {product.stockStatus === 'out_of_stock' ? 'Out of Stock' : 'Add to Cart'}
                  {product.stockStatus !== 'out_of_stock' && <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition-transform" />}
                </button>
              </div>
              {quantity < moq && product.stockStatus !== 'out_of_stock' && (
                <p className="text-xs text-red-400 mt-2 uppercase tracking-wider">Minimum order quantity is {moq} units.</p>
              )}
            </div>

            <button
              onClick={() => setIsQuoteModalOpen(true)}
              className="w-full py-4 border border-slate-200 hover:bg-slate-50 transition-colors uppercase tracking-widest text-sm mb-12"
            >
              Request Custom Quote / Branding
            </button>

            {/* Features */}
            <div className="space-y-4 pt-8 border-t border-slate-200">
              <div className="flex items-center gap-3 text-sm text-slate-700">
                <ShieldCheck className="w-5 h-5" /> 100% Quality Guarantee
              </div>
              <div className="flex items-center gap-3 text-sm text-slate-700">
                <Truck className="w-5 h-5" /> Pan-India Delivery
              </div>
              <div className="flex items-center gap-3 text-sm text-slate-700">
                <Clock className="w-5 h-5" /> 24/7 Dedicated Support
              </div>
            </div>
          </motion.div>
        </div>
      </div>

      {/* Quote Request Modal */}
      {isQuoteModalOpen && (
        <div className="fixed inset-0 bg-slate-900/60 backdrop-blur-sm z-[100] flex items-center justify-center p-4">
          <motion.div
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            className="bg-white border border-slate-200 p-8 max-w-lg w-full relative text-slate-900"
          >
            <button onClick={() => setIsQuoteModalOpen(false)} className="absolute top-4 right-4 text-slate-500 hover:text-slate-900">
              <X className="w-6 h-6" />
            </button>
            <h2 className="text-2xl uppercase tracking-tighter mb-2">Request Quote</h2>
            <p className="text-sm text-slate-600 mb-8 uppercase tracking-wider">For {product.name}</p>

            <form className="space-y-6" onSubmit={(e) => { e.preventDefault(); alert('Quote requested! We\'ll contact you within 24 hours.'); setIsQuoteModalOpen(false); }}>
              <div>
                <label className="block text-xs uppercase tracking-widest mb-2 text-slate-600">Company Name</label>
                <input type="text" required className="w-full bg-transparent border-b border-slate-200 py-2 focus:outline-none focus:border-slate-900 transition-colors" />
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs uppercase tracking-widest mb-2 text-slate-600">Estimated Quantity</label>
                  <input type="number" required defaultValue={quantity} min={moq} className="w-full bg-transparent border-b border-slate-200 py-2 focus:outline-none focus:border-slate-900 transition-colors" />
                </div>
                <div>
                  <label className="block text-xs uppercase tracking-widest mb-2 text-slate-600">Need Branding?</label>
                  <select className="w-full bg-white border-b border-slate-200 py-2 focus:outline-none focus:border-slate-900 transition-colors text-slate-900">
                    <option value="yes">Yes, Print Logo</option>
                    <option value="no">No, Plain Products</option>
                  </select>
                </div>
              </div>
              <div>
                <label className="block text-xs uppercase tracking-widest mb-2 text-slate-600">Email Address</label>
                <input type="email" required className="w-full bg-transparent border-b border-slate-200 py-2 focus:outline-none focus:border-slate-900 transition-colors" />
              </div>
              <button type="submit" className="w-full py-4 bg-slate-900 text-white hover:bg-slate-800 transition-colors uppercase tracking-widest text-sm mt-4">
                Submit Request
              </button>
            </form>
          </motion.div>
        </div>
      )}
    </div>
  );
}
