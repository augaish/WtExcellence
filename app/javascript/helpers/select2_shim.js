// Shim to ensure jQuery is available before Select2 loads
import jQuery from "jquery";

// Expose jQuery globally
window.jQuery = window.$ = jQuery;

// Export jQuery for use in other modules
export default jQuery;
export { jQuery as $, jQuery as jQuery };

