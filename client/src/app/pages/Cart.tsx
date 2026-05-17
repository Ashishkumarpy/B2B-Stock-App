import { useCart } from '../context/CartContext';
import { Link } from 'react-router';
import { Trash2, ArrowRight, Package } from 'lucide-react';
import { motion } from 'motion/react';

export default function Cart() {
  const { items, updateQuantity, removeItem, subtotal, totalQuantity } = useCart();

  const tax = subtotal * 0.18; // 18% GST typical for B2B
  const total = subtotal + tax;

  if (items.length === 0) {
    return (
      <div className="min-h-screen bg-white text-slate-900 pt-36 flex flex-col items-center justify-center">
        <motion.div 
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          className="text-center"
        >
          <div className="w-24 h-24 bg-white/5 border border-white/10 flex items-center justify-center mx-auto mb-6">
            <Package className="w-10 h-10 text-gray-500" />
          </div>
          <h1 className="text-4xl md:text-5xl uppercase tracking-tighter mb-4">Your Cart is Empty</h1>
          <p className="text-gray-400 uppercase tracking-wider mb-8">Ready to order some premium corporate gifts?</p>
          <Link 
            to="/products"
            className="inline-flex px-8 py-4 bg-white text-black hover:bg-gray-200 transition-colors uppercase tracking-widest text-sm"
          >
            Explore Catalog
          </Link>
        </motion.div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-white text-slate-900 pt-36 pb-24">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <h1 className="text-5xl md:text-7xl uppercase tracking-tighter mb-12">Review Cart</h1>

        <div className="grid lg:grid-cols-3 gap-12 lg:gap-16">
          {/* Left: Cart Items */}
          <div className="lg:col-span-2 space-y-8">
            <div className="hidden md:grid grid-cols-12 gap-4 text-xs uppercase tracking-widest text-gray-500 border-b border-white/10 pb-4">
              <div className="col-span-6">Product</div>
              <div className="col-span-3 text-center">Quantity</div>
              <div className="col-span-3 text-right">Total</div>
            </div>

            {items.map((item) => (
              <div key={item.id} className="flex flex-col md:grid md:grid-cols-12 gap-4 items-start md:items-center py-6 border-b border-white/5">
                {/* Product Info */}
                <div className="col-span-6 flex gap-6 w-full">
                  <Link to={`/product/${item.id}`} className="w-24 h-24 bg-white/5 border border-white/10 flex-shrink-0 hover:border-white/30 transition-colors">
                    <img src={item.image} alt={item.name} className="w-full h-full object-cover" />
                  </Link>
                  <div className="flex flex-col justify-center">
                    <Link to={`/product/${item.id}`} className="hover:underline">
                      <h3 className="text-sm uppercase tracking-wider mb-1">{item.name}</h3>
                    </Link>
                    <p className="text-xs text-gray-500 uppercase tracking-widest mb-3">₹{item.price.toLocaleString()} / unit</p>
                    <button 
                      onClick={() => removeItem(item.id)}
                      className="text-xs text-gray-500 hover:text-red-400 uppercase tracking-widest flex items-center gap-1 w-fit transition-colors"
                    >
                      <Trash2 className="w-3 h-3" /> Remove
                    </button>
                  </div>
                </div>

                {/* Quantity */}
                <div className="col-span-3 w-full md:w-auto flex flex-col items-start md:items-center mt-4 md:mt-0">
                  <div className="flex items-center border border-white/20">
                    <button
                      onClick={() => updateQuantity(item.id, item.quantity - 1)}
                      className="px-4 py-2 hover:bg-white/10 transition-colors"
                    >
                      -
                    </button>
                    <input
                      type="number"
                      value={item.quantity}
                      onChange={(e) => updateQuantity(item.id, parseInt(e.target.value) || 0)}
                      className="w-16 bg-transparent text-center text-sm focus:outline-none focus:bg-white/5 py-2"
                      min="0"
                    />
                    <button
                      onClick={() => updateQuantity(item.id, item.quantity + 1)}
                      className="px-4 py-2 hover:bg-white/10 transition-colors"
                    >
                      +
                    </button>
                  </div>
                  {item.quantity < item.moq && (
                    <span className="text-[10px] text-red-400 uppercase tracking-widest mt-2 text-center w-full">
                      MOQ: {item.moq}
                    </span>
                  )}
                </div>

                {/* Subtotal */}
                <div className="col-span-3 text-left md:text-right w-full md:w-auto mt-2 md:mt-0">
                  <span className="md:hidden text-xs text-gray-500 uppercase tracking-widest mr-2">Total:</span>
                  <span className="text-lg tracking-wider">₹{(item.price * item.quantity).toLocaleString()}</span>
                </div>
              </div>
            ))}
          </div>

          {/* Right: Order Summary (Sticky) */}
          <div className="lg:col-span-1">
            <div className="sticky top-32 bg-white/5 border border-white/10 p-8">
              <h2 className="text-xl uppercase tracking-wider mb-8 border-b border-white/10 pb-4">Order Summary</h2>
              
              <div className="space-y-4 mb-8">
                <div className="flex justify-between text-sm uppercase tracking-wider text-gray-400">
                  <span>Subtotal ({totalQuantity} items)</span>
                  <span className="text-white">₹{subtotal.toLocaleString()}</span>
                </div>
                <div className="flex justify-between text-sm uppercase tracking-wider text-gray-400">
                  <span>Estimated GST (18%)</span>
                  <span className="text-white">₹{tax.toLocaleString()}</span>
                </div>
                <div className="flex justify-between text-sm uppercase tracking-wider text-gray-400">
                  <span>Shipping</span>
                  <span className="text-white">Calculated at Checkout</span>
                </div>
              </div>

              <div className="border-t border-white/10 pt-6 mb-8 flex justify-between items-center">
                <span className="uppercase tracking-widest">Estimated Total</span>
                <span className="text-2xl tracking-wider">₹{total.toLocaleString()}</span>
              </div>

              <Link 
                to="/checkout"
                className="w-full flex items-center justify-center gap-2 px-8 py-4 bg-white text-black hover:bg-gray-200 transition-colors text-sm uppercase tracking-widest group"
              >
                Proceed to Checkout
                <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition-transform" />
              </Link>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
