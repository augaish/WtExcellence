/**
 * Helper function to show a confirmation modal
 * 
 * Usage:
 *   const confirmed = await showConfirmationModal(
 *     'Are you sure you want to delete this item?',
 *     { title: 'Confirm Delete', confirmText: 'Delete', buttonStyle: 'danger' }
 *   );
 *   if (confirmed) {
 *     // User confirmed
 *   }
 * 
 * @param {string} message - The message to display
 * @param {object} options - Optional configuration
 * @param {string} options.title - Modal title (default: 'Confirm Action')
 * @param {string} options.confirmText - Confirm button text (default: 'Confirm')
 * @param {string} options.buttonStyle - Button style: 'danger', 'primary', or 'default' (default: 'danger')
 * @returns {Promise<boolean>} - Resolves to true if confirmed, false if cancelled
 */
export async function showConfirmationModal(message, options = {}) {
  const modal = document.getElementById('generalConfirmationModal');
  if (!modal) {
    // Fallback to browser confirm if modal not found
    return confirm(message);
  }

  try {
    // Try to get Stimulus controller
    // Get Stimulus application - window.Stimulus should be set in application.js
    const application = window.Stimulus;
    
    if (!application) {
      return confirm(message);
    }

    if (typeof application.getControllerForElementAndIdentifier !== 'function') {
      return confirm(message);
    }

    const controller = application.getControllerForElementAndIdentifier(
      modal,
      'general-confirmation'
    );

    if (!controller) {
      return confirm(message);
    }

    // Auto-detect button style and text based on message
    const lowerMessage = message.toLowerCase();
    if (!options.buttonStyle) {
      if (lowerMessage.includes('delete')) {
        options.buttonStyle = 'danger';
        options.confirmText = options.confirmText || 'Delete';
        options.title = options.title || 'Confirm Delete';
      } else if (lowerMessage.includes('remove') || lowerMessage.includes('unlink')) {
        options.buttonStyle = 'danger';
        options.confirmText = options.confirmText || 'Remove';
        options.title = options.title || 'Confirm Removal';
      } else {
        options.buttonStyle = options.buttonStyle || 'primary';
      }
    }

    return await controller.confirm(message, options);
  } catch (error) {
    console.error('Error showing confirmation modal:', error);
    return confirm(message);
  }
}

/**
 * Show the dashboard confirmation modal (used on account management and other dashboard pages).
 * Same API as showConfirmationModal but uses dashboardConfirmationModal element.
 */
export async function showDashboardConfirmationModal(message, options = {}) {
  const modal = document.getElementById('dashboardConfirmationModal');
  if (!modal) {
    return confirm(message);
  }

  try {
    const application = window.Stimulus;
    if (!application || typeof application.getControllerForElementAndIdentifier !== 'function') {
      return confirm(message);
    }

    const controller = application.getControllerForElementAndIdentifier(modal, 'general-confirmation');
    if (!controller) {
      return confirm(message);
    }

    const lowerMessage = message.toLowerCase();
    if (!options.buttonStyle) {
      if (lowerMessage.includes('delete')) {
        options.buttonStyle = 'danger';
        options.confirmText = options.confirmText || 'Delete';
        options.title = options.title || 'Confirm Delete';
      } else if (lowerMessage.includes('remove') || lowerMessage.includes('unlink')) {
        options.buttonStyle = 'danger';
        options.confirmText = options.confirmText || 'Remove';
        options.title = options.title || 'Confirm Removal';
      } else {
        options.buttonStyle = options.buttonStyle || 'primary';
      }
    }

    return await controller.confirm(message, options);
  } catch (error) {
    console.error('Error showing dashboard confirmation modal:', error);
    return confirm(message);
  }
}

// Make it available globally for easy access
if (typeof window !== 'undefined') {
  window.showConfirmationModal = showConfirmationModal;
  window.showDashboardConfirmationModal = showDashboardConfirmationModal;
}

