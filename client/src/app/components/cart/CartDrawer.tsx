import { X, Trash2, ArrowRight } from 'lucide-react';
import { useCart } from '../../context/CartContext';
import { Link } from 'react-router';

export function CartDrawer() {
  const { isDrawerOpen, setIsDrawerOpen, items, updateQuantity, removeItem, subtotal, totalQuantity } = useCart();

  return (
    <>
      {/* Overlay */}
      <div
        className={`fixed inset-0 bg-black/60 backdrop-blur-sm z-[60] transition-opacity duration-300 ${
          isDrawerOpen ? 'opacity-100' : 'opacity-0 pointer-events-none'
        }`}
        onClick={() => setIsDrawerOpen(false)}
      />

      {/* Drawer */}
      <div
        className={`fixed top-0 right-0 h-full w-full sm:w-[450px] bg-black border-l border-white/10 z-[70] transform transition-transform duration-300 flex flex-col ${
          isDrawerOpen ? 'translate-x-0' : 'translate-x-full'
        }`}
      >
        {/* Header */}
        <div className="flex items-center justify-between p-6 border-b border-white/10 bg-black">
          <h2 className="text-xl uppercase tracking-wider text-white">Your Cart ({totalQuantity})</h2>
          <button
            onClick={() => setIsDrawerOpen(false)}
            className="text-gray-400 hover:text-white transition-colors p-2"
          >
            <X className="w-6 h-6" />
          </button>
        </div>

        {/* Cart Items */}
        <div className="flex-1 overflow-y-auto p-6 space-y-6">
          {items.length === 0 ? (
            <div className="h-full flex flex-col items-center justify-center text-center text-gray-500 space-y-4">
              <div className="w-20 h-20 bg-white/5 rounded-full flex items-center justify-center border border-white/10">
                <Trash2 className="w-8 h-8 opacity-50" />
              </div>
              <div>
                <p className="uppercase tracking-widest text-sm mb-2 text-white">Your cart is empty</p>
                <p className="text-xs uppercase tracking-wider">Add some premium gifts to get started.</p>
              </div>
              <button 
                onClick={() => setIsDrawerOpen(false)}
                className="px-6 py-3 border border-white/20 text-white text-xs uppercase tracking-wider hover:bg-white/10 transition-colors mt-4"
              >
                Continue Shopping
              </button>
            </div>
          ) : (
            items.map((item) => (
              <div key={item.id} className="flex gap-4 border-b border-white/5 pb-6">
                <div className="w-24 h-24 bg-white/5 border border-white/10 flex-shrink-0">
                  <img src={item.image} alt={item.name} className="w-full h-full object-cover" />
                </div>
                <div className="flex-1 flex flex-col justify-between">
                  <div>
                    <div className="flex justify-between items-start gap-2">
                      <Link to={`/product/${item.id}`} onClick={() => setIsDrawerOpen(false)} className="hover:underline">
                        <h3 className="text-sm uppercase tracking-wider text-white leading-tight">{item.name}</h3>
                      </Link>
                      <button 
                        onClick={() => removeItem(item.id)}
                        className="text-gray-500 hover:text-red-500 transition-colors"
                      >
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </div>
                    <p className="text-xs text-gray-400 uppercase mt-1">₹{item.price.toLocaleString()}</p>
                    {item.quantity < item.moq && (
                       <p className="text-[10px] text-red-400 uppercase mt-1 tracking-wider">MOQ: {item.moq} Units</p>
                    )}
                  </div>
                  <div className="flex items-center gap-3 mt-3">
                    <div className="flex items-center border border-white/20">
                      <button
                        onClick={() => updateQuantity(item.id, item.quantity - 1)}
                        className="px-3 py-1 hover:bg-white/10 text-white transition-colors"
                      >
                        -
                      </button>
                      <input
                        type="number"
                        value={item.quantity}
                        onChange={(e) => updateQuantity(item.id, parseInt(e.target.value) || 0)}
                        className="w-12 bg-transparent text-center text-sm text-white focus:outline-none focus:bg-white/5"
                        min="0"
                      />
                      <button
                        onClick={() => updateQuantity(item.id, item.quantity + 1)}
                        className="px-3 py-1 hover:bg-white/10 text-white transition-colors"
                      >
                        +
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            ))
          )}
        </div>

        {/* Footer Summary */}
        {items.length > 0 && (
          <div className="border-t border-white/10 p-6 bg-black">
            <div className="flex justify-between items-center mb-6">
              <span className="text-sm uppercase tracking-wider text-gray-400">Subtotal</span>
              <span className="text-xl text-white tracking-wider">₹{subtotal.toLocaleString()}</span>
            </div>
            
            <Link 
              to="/checkout"
              onClick={() => setIsDrawerOpen(false)}
              className="w-full flex items-center justify-center gap-2 px-8 py-4 bg-white text-black hover:bg-gray-200 transition-colors text-sm uppercase tracking-widest group"
            >
              Proceed to Checkout
              <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition-transform" />
            </Link>
            
            <Link 
              to="/cart"
              onClick={() => setIsDrawerOpen(false)}
              className="w-full flex items-center justify-center mt-3 px-8 py-3 border border-white/20 text-white hover:bg-white/10 transition-colors text-xs uppercase tracking-widest"
            >
              View Full Cart
            </Link>
          </div>
        )}
      </div>
    </>
  );
}
