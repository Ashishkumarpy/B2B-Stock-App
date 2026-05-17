import { motion } from 'motion/react';
import { ArrowRight, Mail, Phone, MapPin } from 'lucide-react';

const productCategories = [
  'Bags',
  'Card Holders',
  'Electronics',
  'Gift Sets & Combos',
  'Diwali Catalogue',
  'ID Cards',
  'Keychains & Badge Reels',
  'Water Bottles',
  'Mugs',
  'Notebooks & Diaries',
];

export default function Contact() {
  return (
    <div className="min-h-screen bg-white text-slate-900 pt-36">
      {/* Hero Section */}
      <section className="py-20 border-b border-white/10">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.8 }}
          >
            <h1 className="text-6xl md:text-8xl tracking-tighter uppercase mb-6">
              GET IN TOUCH
            </h1>
            <p className="text-lg text-gray-400 uppercase tracking-wider max-w-2xl">
              Request a quote and we&apos;ll respond within 24 hours
            </p>
          </motion.div>
        </div>
      </section>

      {/* Contact Form & Info */}
      <section className="py-24">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="grid lg:grid-cols-2 gap-16">
            {/* Contact Form */}
            <motion.div
              initial={{ opacity: 0, x: -20 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ duration: 0.8, delay: 0.2 }}
            >
              <h2 className="text-3xl md:text-4xl tracking-tighter uppercase mb-10">
                REQUEST A QUOTE
              </h2>

              <form className="space-y-8">
                <div className="grid md:grid-cols-2 gap-6">
                  <div>
                    <label className="block mb-3 text-xs uppercase tracking-widest">
                      Your Name *
                    </label>
                    <input
                      type="text"
                      className="w-full px-0 py-3 border-0 border-b border-white/20 bg-transparent text-white placeholder-gray-500 focus:outline-none focus:border-white transition-colors"
                      placeholder="JOHN DOE"
                      required
                    />
                  </div>
                  <div>
                    <label className="block mb-3 text-xs uppercase tracking-widest">
                      Company Name *
                    </label>
                    <input
                      type="text"
                      className="w-full px-0 py-3 border-0 border-b border-white/20 bg-transparent text-white placeholder-gray-500 focus:outline-none focus:border-white transition-colors"
                      placeholder="ABC CORPORATION"
                      required
                    />
                  </div>
                </div>

                <div className="grid md:grid-cols-2 gap-6">
                  <div>
                    <label className="block mb-3 text-xs uppercase tracking-widest">
                      Email Address *
                    </label>
                    <input
                      type="email"
                      className="w-full px-0 py-3 border-0 border-b border-white/20 bg-transparent text-white placeholder-gray-500 focus:outline-none focus:border-white transition-colors"
                      placeholder="JOHN@COMPANY.COM"
                      required
                    />
                  </div>
                  <div>
                    <label className="block mb-3 text-xs uppercase tracking-widest">
                      Phone Number *
                    </label>
                    <input
                      type="tel"
                      className="w-full px-0 py-3 border-0 border-b border-white/20 bg-transparent text-white placeholder-gray-500 focus:outline-none focus:border-white transition-colors"
                      placeholder="+91 98765 43210"
                      required
                    />
                  </div>
                </div>

                <div className="grid md:grid-cols-2 gap-6">
                  <div>
                    <label className="block mb-3 text-xs uppercase tracking-widest">
                      Quantity Required *
                    </label>
                    <select className="w-full px-0 py-3 border-0 border-b border-white/20 bg-transparent text-white focus:outline-none focus:border-white transition-colors">
                      <option className="bg-white" value="">
                        SELECT QUANTITY RANGE
                      </option>
                      <option className="bg-white" value="50-100">
                        50-100 UNITS
                      </option>
                      <option className="bg-white" value="100-500">
                        100-500 UNITS
                      </option>
                      <option className="bg-white" value="500-1000">
                        500-1000 UNITS
                      </option>
                      <option className="bg-white" value="1000+">
                        1000+ UNITS
                      </option>
                    </select>
                  </div>
                  <div>
                    <label className="block mb-3 text-xs uppercase tracking-widest">
                      Product Interest *
                    </label>
                    <select className="w-full px-0 py-3 border-0 border-b border-white/20 bg-transparent text-white focus:outline-none focus:border-white transition-colors">
                      <option className="bg-white" value="">
                        SELECT CATEGORY
                      </option>
                      {productCategories.map((cat) => (
                        <option key={cat} className="bg-white" value={cat}>
                          {cat.toUpperCase()}
                        </option>
                      ))}
                    </select>
                  </div>
                </div>

                <div>
                  <label className="block mb-3 text-xs uppercase tracking-widest">
                    Additional Requirements
                  </label>
                  <textarea
                    className="w-full px-0 py-3 border-0 border-b border-white/20 bg-transparent text-white placeholder-gray-500 focus:outline-none focus:border-white transition-colors resize-none"
                    rows={3}
                    placeholder="TELL US ABOUT YOUR REQUIREMENTS..."
                  ></textarea>
                </div>

                <button
                  type="submit"
                  className="w-full px-8 py-5 bg-white text-black hover:bg-gray-200 transition-colors text-sm uppercase tracking-widest flex items-center justify-center gap-2 group"
                >
                  Submit Request
                  <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition-transform" />
                </button>
              </form>
            </motion.div>

            {/* Contact Information */}
            <motion.div
              initial={{ opacity: 0, x: 20 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ duration: 0.8, delay: 0.4 }}
              className="lg:pl-16"
            >
              <h2 className="text-3xl md:text-4xl tracking-tighter uppercase mb-10">
                CONTACT INFO
              </h2>

              <div className="space-y-10 mb-16">
                <div className="flex gap-6">
                  <div className="w-12 h-12 border border-white/20 flex items-center justify-center flex-shrink-0">
                    <Mail className="w-5 h-5" />
                  </div>
                  <div>
                    <h3 className="text-sm uppercase tracking-widest mb-2 text-gray-400">
                      Email
                    </h3>
                    <a
                      href="mailto:info@giftpro.com"
                      className="text-xl hover:text-gray-300 transition-colors"
                    >
                      info@giftpro.com
                    </a>
                  </div>
                </div>

                <div className="flex gap-6">
                  <div className="w-12 h-12 border border-white/20 flex items-center justify-center flex-shrink-0">
                    <Phone className="w-5 h-5" />
                  </div>
                  <div>
                    <h3 className="text-sm uppercase tracking-widest mb-2 text-gray-400">
                      Phone
                    </h3>
                    <a
                      href="tel:+919876543210"
                      className="text-xl hover:text-gray-300 transition-colors"
                    >
                      +91 98765 43210
                    </a>
                  </div>
                </div>

                <div className="flex gap-6">
                  <div className="w-12 h-12 border border-white/20 flex items-center justify-center flex-shrink-0">
                    <MapPin className="w-5 h-5" />
                  </div>
                  <div>
                    <h3 className="text-sm uppercase tracking-widest mb-2 text-gray-400">
                      Address
                    </h3>
                    <p className="text-xl">
                      123 Business Park,
                      <br />
                      Mumbai, India 400001
                    </p>
                  </div>
                </div>
              </div>

              <div className="border-t border-white/10 pt-10">
                <h3 className="text-sm uppercase tracking-widest mb-6 text-gray-400">
                  Business Hours
                </h3>
                <div className="space-y-3 text-lg">
                  <div className="flex justify-between">
                    <span className="text-gray-400">Monday - Friday</span>
                    <span>9:00 AM - 6:00 PM</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-gray-400">Saturday</span>
                    <span>10:00 AM - 4:00 PM</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-gray-400">Sunday</span>
                    <span>Closed</span>
                  </div>
                </div>
              </div>
            </motion.div>
          </div>
        </div>
      </section>

      {/* Why Choose Us Banner */}
      <section className="py-24 bg-white text-black">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
          <h2 className="text-4xl md:text-5xl tracking-tighter uppercase mb-6">
            TRUSTED BY 500+ COMPANIES
          </h2>
          <p className="text-lg text-gray-600 uppercase tracking-wider mb-10 max-w-2xl mx-auto">
            Join leading brands who trust us for their corporate gifting needs
          </p>
          <div className="flex flex-wrap justify-center items-center gap-12 opacity-40 mt-12">
            {['TECHCORP', 'INNOVATELABS', 'GLOBALBANK', 'HEALTHPLUS', 'EDUTECH'].map((company) => (
              <div key={company} className="text-xl tracking-wider uppercase">
                {company}
              </div>
            ))}
          </div>
        </div>
      </section>
    </div>
  );
}
