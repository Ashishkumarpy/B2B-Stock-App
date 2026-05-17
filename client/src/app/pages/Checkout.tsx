import { useState, useRef } from 'react';
import { useCart } from '../context/CartContext';
import { Link, useNavigate } from 'react-router';
import { motion, AnimatePresence } from 'motion/react';
import { ArrowRight, ArrowLeft, Check, CheckCircle2, Loader2, Upload, X } from 'lucide-react';
import { supabase } from '../../lib/supabase';

const steps = ['Branding', 'Contact Info', 'Shipping Details', 'Payment Options', 'Review & Confirm'];

export default function Checkout() {
  const [currentStep, setCurrentStep] = useState(0);
  const { items, subtotal, totalQuantity, clearCart } = useCart();
  const navigate = useNavigate();

  const tax = subtotal * 0.18;
  const total = subtotal + tax;

  const [isSuccess, setIsSuccess] = useState(false);
  const [isPlacingOrder, setIsPlacingOrder] = useState(false);
  const [orderRef, setOrderRef] = useState('');

  // Form State
  const [formData, setFormData] = useState({
    firstName: '',
    lastName: '',
    companyName: '',
    email: '',
    phone: '',
    address1: '',
    address2: '',
    city: '',
    state: '',
    postalCode: '',
    country: 'India',
    paymentMethod: 'Pay by Invoice (Net 30)',
    brandingNotes: '',
  });

  const [logoFile, setLogoFile] = useState<File | null>(null);
  const [logoPreview, setLogoPreview] = useState<string>('');
  const [isUploadingLogo, setIsUploadingLogo] = useState(false);
  const logoInputRef = useRef<HTMLInputElement>(null);

  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>) => {
    const { name, value } = e.target;
    setFormData(prev => ({ ...prev, [name]: value }));
  };

  const handleLogoChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      setLogoFile(file);
      const reader = new FileReader();
      reader.onloadend = () => setLogoPreview(reader.result as string);
      reader.readAsDataURL(file);
    }
  };

  const handleNext = async () => {
    if (currentStep < steps.length - 1) {
      setCurrentStep((prev) => prev + 1);
    } else {
      // Place Order
      setIsPlacingOrder(true);
      try {
        let logoUrl = '';
        if (logoFile) {
          setIsUploadingLogo(true);
          const logoPath = `order-logos/${Date.now()}_${logoFile.name}`;
          const { error: uploadError } = await supabase.storage.from('assets').upload(logoPath, logoFile);
          if (uploadError) throw uploadError;
          const { data: publicUrlData } = supabase.storage.from('assets').getPublicUrl(logoPath);
          logoUrl = publicUrlData.publicUrl;
          setIsUploadingLogo(false);
        }

        const orderData = {
          customerName: `${formData.firstName} ${formData.lastName}`,
          companyName: formData.companyName,
          email: formData.email,
          phone: formData.phone,
          shippingAddress: {
            address1: formData.address1,
            address2: formData.address2,
            city: formData.city,
            state: formData.state,
            postalCode: formData.postalCode,
            country: formData.country,
          },
          items: items.map(item => ({
            id: item.id,
            name: item.name,
            quantity: item.quantity,
            price: item.price,
            total: item.price * item.quantity,
          })),
          subtotal,
          tax,
          total,
          totalQuantity,
          status: 'pending',
          paymentMethod: formData.paymentMethod,
          branding: {
            logoUrl,
            notes: formData.brandingNotes,
          },
          createdAt: new Date().toISOString(),
        };

        const { data: docData, error: insertError } = await supabase.from('orders').insert([orderData]).select().single();
        if (insertError) throw insertError;
        setOrderRef(docData.id.slice(-6).toUpperCase());
        setIsSuccess(true);
        clearCart();
      } catch (error) {
        console.error("Error placing order: ", error);
        alert("Failed to place order. Please try again.");
      } finally {
        setIsPlacingOrder(false);
        setIsUploadingLogo(false);
      }
    }
  };

  const handleBack = () => {
    if (currentStep > 0) {
      setCurrentStep((prev) => prev - 1);
    }
  };

  if (items.length === 0 && !isSuccess) {
    return (
      <div className="min-h-screen bg-white text-slate-900 pt-36 flex flex-col items-center justify-center">
        <h1 className="text-4xl uppercase tracking-tighter mb-4">No items to checkout</h1>
        <Link to="/products" className="text-gray-400 hover:text-white uppercase tracking-widest text-sm underline">
          Return to Catalog
        </Link>
      </div>
    );
  }

  if (isSuccess) {
    return (
      <div className="min-h-screen bg-white text-slate-900 pt-36 flex flex-col items-center justify-center">
        <motion.div 
          initial={{ opacity: 0, scale: 0.9 }}
          animate={{ opacity: 1, scale: 1 }}
          className="text-center p-8 bg-white/5 border border-white/10 max-w-lg w-full mx-4"
        >
          <div className="w-20 h-20 bg-green-500/10 text-green-500 rounded-full flex items-center justify-center mx-auto mb-6">
            <CheckCircle2 className="w-10 h-10" />
          </div>
          <h1 className="text-3xl uppercase tracking-tighter mb-4">Order Received</h1>
          <p className="text-gray-400 uppercase tracking-wider text-sm leading-relaxed mb-8">
            Thank you for your order! Your B2B Account Manager will contact you shortly to confirm branding details and shipping timeline.
          </p>
          <div className="text-xs text-gray-500 uppercase tracking-widest mb-8">
            Order Reference: #XG-{orderRef}
          </div>
          <Link 
            to="/"
            className="inline-block px-12 py-4 bg-white text-black hover:bg-gray-200 transition-colors uppercase tracking-widest text-sm"
          >
            Back to Home
          </Link>
        </motion.div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-white text-slate-900 pt-36 pb-24">
      <div className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8">
        
        {/* Stepper */}
        <div className="mb-12">
          <div className="flex items-center justify-between relative">
            <div className="absolute left-0 top-1/2 -translate-y-1/2 w-full h-[1px] bg-white/10 z-0"></div>
            <div className="absolute left-0 top-1/2 -translate-y-1/2 h-[1px] bg-white z-0 transition-all duration-500" style={{ width: `${(currentStep / (steps.length - 1)) * 100}%` }}></div>
            
            {steps.map((step, index) => {
              const isCompleted = index < currentStep;
              const isActive = index === currentStep;
              return (
                <div key={step} className="relative z-10 flex flex-col items-center">
                  <div className={`w-8 h-8 rounded-full flex items-center justify-center text-xs border transition-colors ${
                    isActive ? 'bg-white text-black border-white' : 
                    isCompleted ? 'bg-slate-900 text-white border-slate-900' : 
                    'bg-white text-slate-600 border-slate-200'
                  }`}>
                    {isCompleted ? <Check className="w-4 h-4" /> : index + 1}
                  </div>
                  <span className={`absolute top-10 text-[10px] uppercase tracking-widest whitespace-nowrap hidden sm:block ${
                    isActive ? 'text-white' : isCompleted ? 'text-gray-400' : 'text-gray-600'
                  }`}>
                    {step}
                  </span>
                </div>
              );
            })}
          </div>
        </div>

        <div className="grid lg:grid-cols-3 gap-12 sm:mt-24 mt-12">
          {/* Left: Form Area */}
          <div className="lg:col-span-2 relative overflow-hidden min-h-[450px]">
            <AnimatePresence mode="wait">
              {currentStep === 0 && (
                <motion.div
                  key="step0"
                  initial={{ opacity: 0, x: 20 }}
                  animate={{ opacity: 1, x: 0 }}
                  exit={{ opacity: 0, x: -20 }}
                  className="space-y-6"
                >
                  <h2 className="text-2xl uppercase tracking-wider mb-6">Branding Options</h2>
                  <p className="text-xs uppercase tracking-widest text-gray-400 mb-8">Upload your company logo for custom product branding</p>
                  
                  <div 
                    onClick={() => logoInputRef.current?.click()}
                    className={`border-2 border-dashed rounded-xl p-12 flex flex-col items-center justify-center cursor-pointer transition-colors ${logoPreview ? 'border-white/40 bg-white/5' : 'border-white/10 hover:border-white/20 hover:bg-white/5'}`}
                  >
                    {logoPreview ? (
                      <div className="relative group">
                        <img src={logoPreview} alt="Logo Preview" className="max-h-40 object-contain" />
                        <button 
                          onClick={(e) => { e.stopPropagation(); setLogoPreview(''); setLogoFile(null); }}
                          className="absolute -top-4 -right-4 w-8 h-8 bg-white text-black rounded-full flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity"
                        >
                          <X className="w-4 h-4" />
                        </button>
                      </div>
                    ) : (
                      <>
                        <div className="w-16 h-16 bg-white/5 rounded-full flex items-center justify-center mb-4 text-gray-400">
                          <Upload className="w-8 h-8" />
                        </div>
                        <p className="text-xs uppercase tracking-widest text-gray-400">Click to upload SVG, PNG or AI file</p>
                      </>
                    )}
                  </div>
                  <input ref={logoInputRef} type="file" className="hidden" accept="image/*" onChange={handleLogoChange} />
                  
                  <div>
                    <label className="block text-xs uppercase tracking-widest text-gray-400 mb-2">Special Branding Notes</label>
                    <textarea 
                      name="brandingNotes" 
                      value={formData.brandingNotes} 
                      onChange={handleInputChange}
                      className="w-full bg-white text-black px-4 py-3 focus:outline-none focus:ring-2 focus:ring-gray-400 h-24 resize-none" 
                      placeholder="e.g. Logo placement on bottom right, pantone colors..."
                    />
                  </div>
                </motion.div>
              )}

              {currentStep === 1 && (
                <motion.div
                  key="step1"
                  initial={{ opacity: 0, x: 20 }}
                  animate={{ opacity: 1, x: 0 }}
                  exit={{ opacity: 0, x: -20 }}
                  className="space-y-6"
                >
                  <h2 className="text-2xl uppercase tracking-wider mb-6">Contact Information</h2>
                  <div className="grid md:grid-cols-2 gap-6">
                    <div>
                      <label className="block text-xs uppercase tracking-widest text-gray-400 mb-2">First Name</label>
                      <input type="text" name="firstName" value={formData.firstName} onChange={handleInputChange} className="w-full bg-white text-black px-4 py-3 focus:outline-none focus:ring-2 focus:ring-gray-400" />
                    </div>
                    <div>
                      <label className="block text-xs uppercase tracking-widest text-gray-400 mb-2">Last Name</label>
                      <input type="text" name="lastName" value={formData.lastName} onChange={handleInputChange} className="w-full bg-white text-black px-4 py-3 focus:outline-none focus:ring-2 focus:ring-gray-400" />
                    </div>
                  </div>
                  <div>
                    <label className="block text-xs uppercase tracking-widest text-gray-400 mb-2">Company Name</label>
                    <input type="text" name="companyName" value={formData.companyName} onChange={handleInputChange} className="w-full bg-white text-black px-4 py-3 focus:outline-none focus:ring-2 focus:ring-gray-400" />
                  </div>
                  <div>
                    <label className="block text-xs uppercase tracking-widest text-gray-400 mb-2">Email Address</label>
                    <input type="email" name="email" value={formData.email} onChange={handleInputChange} className="w-full bg-white text-black px-4 py-3 focus:outline-none focus:ring-2 focus:ring-gray-400" />
                  </div>
                  <div>
                    <label className="block text-xs uppercase tracking-widest text-gray-400 mb-2">Phone Number</label>
                    <input type="tel" name="phone" value={formData.phone} onChange={handleInputChange} className="w-full bg-white text-black px-4 py-3 focus:outline-none focus:ring-2 focus:ring-gray-400" />
                  </div>
                </motion.div>
              )}

              {currentStep === 2 && (
                <motion.div
                  key="step2"
                  initial={{ opacity: 0, x: 20 }}
                  animate={{ opacity: 1, x: 0 }}
                  exit={{ opacity: 0, x: -20 }}
                  className="space-y-6"
                >
                  <h2 className="text-2xl uppercase tracking-wider mb-6">Shipping Details</h2>
                  <div>
                    <label className="block text-xs uppercase tracking-widest text-gray-400 mb-2">Address Line 1</label>
                    <input type="text" name="address1" value={formData.address1} onChange={handleInputChange} className="w-full bg-white text-black px-4 py-3 focus:outline-none focus:ring-2 focus:ring-gray-400" />
                  </div>
                  <div>
                    <label className="block text-xs uppercase tracking-widest text-gray-400 mb-2">Address Line 2 (Optional)</label>
                    <input type="text" name="address2" value={formData.address2} onChange={handleInputChange} className="w-full bg-white text-black px-4 py-3 focus:outline-none focus:ring-2 focus:ring-gray-400" />
                  </div>
                  <div className="grid md:grid-cols-2 gap-6">
                    <div>
                      <label className="block text-xs uppercase tracking-widest text-gray-400 mb-2">City</label>
                      <input type="text" name="city" value={formData.city} onChange={handleInputChange} className="w-full bg-white text-black px-4 py-3 focus:outline-none focus:ring-2 focus:ring-gray-400" />
                    </div>
                    <div>
                      <label className="block text-xs uppercase tracking-widest text-gray-400 mb-2">State / Province</label>
                      <input type="text" name="state" value={formData.state} onChange={handleInputChange} className="w-full bg-white text-black px-4 py-3 focus:outline-none focus:ring-2 focus:ring-gray-400" />
                    </div>
                  </div>
                  <div className="grid md:grid-cols-2 gap-6">
                    <div>
                      <label className="block text-xs uppercase tracking-widest text-gray-400 mb-2">Postal Code</label>
                      <input type="text" name="postalCode" value={formData.postalCode} onChange={handleInputChange} className="w-full bg-white text-black px-4 py-3 focus:outline-none focus:ring-2 focus:ring-gray-400" />
                    </div>
                    <div>
                      <label className="block text-xs uppercase tracking-widest text-gray-400 mb-2">Country</label>
                      <select name="country" value={formData.country} onChange={handleInputChange} className="w-full bg-white text-black px-4 py-3 focus:outline-none focus:ring-2 focus:ring-gray-400 appearance-none">
                        <option>India</option>
                        <option>United States</option>
                        <option>United Kingdom</option>
                      </select>
                    </div>
                  </div>
                </motion.div>
              )}

              {currentStep === 3 && (
                <motion.div
                  key="step3"
                  initial={{ opacity: 0, x: 20 }}
                  animate={{ opacity: 1, x: 0 }}
                  exit={{ opacity: 0, x: -20 }}
                  className="space-y-6"
                >
                  <h2 className="text-2xl uppercase tracking-wider mb-6">Payment Options</h2>
                  <div className="space-y-4">
                    <label className="flex items-center gap-4 p-6 border border-white/20 bg-white/5 cursor-pointer hover:bg-white/10 transition-colors">
                      <input type="radio" name="payment" className="w-5 h-5 accent-white" defaultChecked />
                      <div>
                        <div className="uppercase tracking-widest text-sm mb-1">Pay by Invoice (Net 30)</div>
                        <div className="text-xs text-gray-400 tracking-wider">Subject to credit approval</div>
                      </div>
                    </label>
                    <label className="flex items-center gap-4 p-6 border border-white/20 cursor-pointer hover:bg-white/5 transition-colors opacity-50">
                      <input type="radio" name="payment" className="w-5 h-5 accent-white" disabled />
                      <div>
                        <div className="uppercase tracking-widest text-sm mb-1">Credit Card (Coming Soon)</div>
                        <div className="text-xs text-gray-400 tracking-wider">Online payments will be available shortly</div>
                      </div>
                    </label>
                    <label className="flex items-center gap-4 p-6 border border-white/20 cursor-pointer hover:bg-white/5 transition-colors opacity-50">
                      <input type="radio" name="payment" className="w-5 h-5 accent-white" disabled />
                      <div>
                        <div className="uppercase tracking-widest text-sm mb-1">Bank Transfer (NEFT/RTGS)</div>
                        <div className="text-xs text-gray-400 tracking-wider">Details provided after order confirmation</div>
                      </div>
                    </label>
                  </div>
                </motion.div>
              )}

              {currentStep === 4 && (
                <motion.div
                  key="step4"
                  initial={{ opacity: 0, x: 20 }}
                  animate={{ opacity: 1, x: 0 }}
                  exit={{ opacity: 0, x: -20 }}
                  className="space-y-8"
                >
                  <h2 className="text-2xl uppercase tracking-wider mb-6">Review & Confirm</h2>
                  
                  <div className="bg-white/5 border border-white/10 p-6 space-y-6">
                    <div className="flex gap-6 items-start">
                      <div className="flex-1">
                        <h3 className="text-xs text-gray-500 uppercase tracking-widest mb-2">Contact Details</h3>
                        <p className="text-sm uppercase tracking-wider">{formData.firstName} {formData.lastName} ({formData.companyName})</p>
                        <p className="text-sm text-gray-400 uppercase tracking-wider">{formData.email} | {formData.phone}</p>
                      </div>
                      {logoPreview && (
                        <div className="w-20 h-20 bg-white/5 border border-white/10 rounded flex items-center justify-center overflow-hidden">
                          <img src={logoPreview} alt="Order Logo" className="max-w-full max-h-full object-contain" />
                        </div>
                      )}
                    </div>
                    <div className="border-t border-white/10 pt-6">
                      <h3 className="text-xs text-gray-500 uppercase tracking-widest mb-2">Shipping Address</h3>
                      <p className="text-sm text-gray-400 tracking-wide uppercase leading-relaxed">
                        {formData.address1}<br />
                        {formData.address2 && <>{formData.address2}<br /></>}
                        {formData.city}, {formData.state} {formData.postalCode}<br />
                        {formData.country}
                      </p>
                    </div>
                    <div className="border-t border-white/10 pt-6">
                      <h3 className="text-xs text-gray-500 uppercase tracking-widest mb-2">Payment Method</h3>
                      <p className="text-sm uppercase tracking-wider">{formData.paymentMethod}</p>
                    </div>
                  </div>
                </motion.div>
              )}
            </AnimatePresence>

            {/* Navigation Buttons */}
            <div className="flex items-center justify-between mt-12 pt-8 border-t border-white/10">
              {currentStep > 0 ? (
                <button 
                  onClick={handleBack}
                  disabled={isPlacingOrder}
                  className="flex items-center gap-2 text-sm uppercase tracking-widest text-gray-400 hover:text-white transition-colors disabled:opacity-50"
                >
                  <ArrowLeft className="w-4 h-4" /> Back
                </button>
              ) : (
                <Link to="/cart" className="flex items-center gap-2 text-sm uppercase tracking-widest text-gray-400 hover:text-white transition-colors">
                  <ArrowLeft className="w-4 h-4" /> Return to Cart
                </Link>
              )}
              
              <button 
                onClick={handleNext}
                disabled={isPlacingOrder || (currentStep === 0 && !logoFile && !formData.brandingNotes)}
                className="flex items-center gap-2 px-8 py-4 bg-white text-black hover:bg-gray-200 transition-colors text-sm uppercase tracking-widest group disabled:opacity-50"
              >
                {isPlacingOrder ? (
                  <Loader2 className="w-4 h-4 animate-spin" />
                ) : (
                  <>
                    {currentStep === steps.length - 1 ? 'Place Order' : 'Continue'}
                    {currentStep !== steps.length - 1 && <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition-transform" />}
                  </>
                )}
              </button>
            </div>
          </div>

          {/* Right: Order Summary (Sticky) */}
          <div className="lg:col-span-1">
            <div className="sticky top-32 bg-white/5 border border-white/10 p-6 sm:p-8">
              <h2 className="text-lg uppercase tracking-wider mb-6 border-b border-white/10 pb-4">Order Summary</h2>
              
              <div className="space-y-4 mb-6 max-h-64 overflow-y-auto pr-2">
                {items.map((item) => (
                  <div key={item.id} className="flex gap-4">
                    <div className="w-16 h-16 bg-white/5 border border-white/10 flex-shrink-0">
                      <img src={item.image} alt={item.name} className="w-full h-full object-cover" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <h4 className="text-xs uppercase tracking-wider truncate mb-1">{item.name}</h4>
                      <div className="text-[10px] text-gray-400 uppercase tracking-widest">Qty: {item.quantity}</div>
                      <div className="text-xs uppercase tracking-widest mt-1">₹{(item.price * item.quantity).toLocaleString()}</div>
                    </div>
                  </div>
                ))}
              </div>

              <div className="space-y-4 mb-6 border-t border-white/10 pt-6">
                <div className="flex justify-between text-xs uppercase tracking-widest text-gray-400">
                  <span>Subtotal</span>
                  <span className="text-white">₹{subtotal.toLocaleString()}</span>
                </div>
                <div className="flex justify-between text-xs uppercase tracking-widest text-gray-400">
                  <span>GST (18%)</span>
                  <span className="text-white">₹{tax.toLocaleString()}</span>
                </div>
              </div>

              <div className="border-t border-white/10 pt-6 flex justify-between items-center">
                <span className="text-sm uppercase tracking-widest">Total</span>
                <span className="text-xl tracking-wider">₹{total.toLocaleString()}</span>
              </div>
            </div>
          </div>

        </div>
      </div>
    </div>
  );
}
