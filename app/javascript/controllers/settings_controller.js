import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [
        // Form & Submission
        "form",
        "saveButton",
        "discardButton",
        
        // Profile Image
        "profileImage",
        "profileImageContainer",
        "profileInitials",
        "changeImageButton",
        "removeImageButton",
        "imageInput",
        "removeImageFlag",
        
        // Name Field
        "nameField",
        "nameDisplay",
        "nameInput",
        "nameEditButton",
        
        // Email Field
        "emailField",
        "emailDisplay",
        "emailInput",
        "emailEditButton",
        
        // Platform Settings
        "emailNotificationsToggle",
        "emailNotificationsInput",
        "notificationFrequencySelect",
        "notificationTimeSelect",
        "exportDataButton",
        "deleteAccountButton"
      ]




  connect() {
    // Store initial image state
    this.storeInitialImageState()
  }

  storeInitialImageState() {
    // Store initial image URL if image exists and is visible
    if (this.hasProfileImageTarget && this.profileImageTarget) {
      const src = this.profileImageTarget.src
      const isVisible = !this.profileImageTarget.classList.contains('hidden') && src && src.trim() !== ''
      if (isVisible) {
        this.initialImageUrl = src
        this.initialImageVisible = true
      } else {
        this.initialImageUrl = null
        this.initialImageVisible = false
      }
    } else {
      this.initialImageUrl = null
      this.initialImageVisible = false
    }
    
    // Store initial initials visibility
    if (this.hasProfileInitialsTarget) {
      this.initialInitialsVisible = !this.profileInitialsTarget.classList.contains('hidden')
    } else {
      this.initialInitialsVisible = false
    }
  }

  editName() {
    this.toggleEditMode('name')
  }

  editEmail() {
    this.toggleEditMode('email')
  }

  toggleEditMode(fieldType) {
    const display = this[`${fieldType}DisplayTarget`]
    const hasInput = this[`has${fieldType.charAt(0).toUpperCase() + fieldType.slice(1)}InputTarget`]
    const hasEditButton = this[`has${fieldType.charAt(0).toUpperCase() + fieldType.slice(1)}EditButtonTarget`]
    
    if (!hasInput) return
    
    const input = this[`${fieldType}InputTarget`]
    const editButton = hasEditButton ? this[`${fieldType}EditButtonTarget`] : null
    
    // Toggle visibility
    display.classList.toggle('hidden')
    input.classList.toggle('hidden')
    
    // If switching to edit mode, focus the input
    if (!input.classList.contains('hidden')) {
      input.focus()
      input.select() // Select all text for easy editing
    }
  }

  syncEmailNotificationsToggle() {
    if (this.hasEmailNotificationsToggleTarget && this.hasEmailNotificationsInputTarget) {
      this.emailNotificationsInputTarget.value = this.emailNotificationsToggleTarget.checked ? '1' : '0'
    }
  }

  saveChanges() {
    if (!this.hasFormTarget) return

    // Sync email notifications toggle into form before submit
    this.syncEmailNotificationsToggle()

    const form = this.formTarget
    const formData = new FormData(form)
    
    // Get translated button texts from data attributes
    const saveText = this.saveButtonTarget.dataset.saveText || "Save Changes"
    const savingText = this.saveButtonTarget.dataset.savingText || "Saving..."
    
    // Disable save button during submission
    this.saveButtonTarget.disabled = true
    this.saveButtonTarget.textContent = savingText

    fetch(form.action, {
      method: form.method,
      body: formData,
      headers: {
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
        'Accept': 'application/json'
      },
      credentials: 'same-origin'
    })
    .then(response => response.json())
    .then(data => {
      if (data.success) {
        // Update display values
        this.updateDisplayValues(data.user)
        
        // Exit edit mode for all fields
        this.exitEditMode('name')
        this.exitEditMode('email')
        
        // Show success message (you can enhance this with a toast/notification)
        this.showMessage("Settings saved successfully!", "success")
      } else {
        // Show errors
        this.showMessage(data.errors.join(", "), "error")
      }
    })
    .catch(error => {
      console.error("Error:", error)
      this.showMessage("An error occurred. Please try again.", "error")
    })
    .finally(() => {
      // Re-enable save button
      this.saveButtonTarget.disabled = false
      this.saveButtonTarget.textContent = saveText
    })
  }

  updateDisplayValues(user) {
    // Update name display
    if (user.name) {
      this.nameDisplayTarget.textContent = user.name || "Not set"
    }
    
    // Update email display
    if (user.email) {
      this.emailDisplayTarget.textContent = user.email
    }
    
    // Update profile image if provided, otherwise remove it
    if (user.profile_image_url) {
      this.updateProfileImage(user.profile_image_url)
    } else {
      // Image was removed - hide image and show initials
      if (this.hasProfileImageTarget) {
        this.profileImageTarget.classList.add('hidden')
        this.profileImageTarget.src = ''
      }
      if (this.hasProfileInitialsTarget) {
        this.profileInitialsTarget.classList.remove('hidden')
      }
      // Reset the remove flag
      if (this.hasRemoveImageFlagTarget) {
        this.removeImageFlagTarget.value = '0'
      }
    }

    // Sync email notifications toggle and hidden input from server response
    if (user.receive_notifications_on_email !== undefined && this.hasEmailNotificationsToggleTarget && this.hasEmailNotificationsInputTarget) {
      const on = !!user.receive_notifications_on_email
      this.emailNotificationsToggleTarget.checked = on
      this.emailNotificationsInputTarget.value = on ? '1' : '0'
    }

    // Store new state as initial after successful save
    this.storeInitialImageState()
    
    // Update navbar profile image
    this.updateNavbarProfileImage(user.profile_image_url, user.name)
  }

  updateNavbarProfileImage(imageUrl, userName) {
    const navbarContainer = document.querySelector('[data-navbar-profile-container]')
    if (!navbarContainer) return
    
    // Get or create initials
    const getInitials = (name) => {
      if (!name) return 'U'
      const parts = name.split(' ')
      return (parts[0]?.[0] || '') + (parts[1]?.[0] || '')
    }
    
    // Update the name in the navbar
    const nameElement = document.querySelector('[data-navbar-profile-name]')
    if (nameElement && userName) {
      nameElement.textContent = userName
    }
    
    if (imageUrl) {
      // Show image, hide initials
      let imgElement = navbarContainer.querySelector('[data-navbar-profile-image]')
      const initialsElement = navbarContainer.querySelector('[data-navbar-profile-initials]')
      
      if (!imgElement) {
        // Create img element if it doesn't exist
        imgElement = document.createElement('img')
        imgElement.className = "w-full h-full object-cover"
        imgElement.setAttribute('data-navbar-profile-image', 'true')
        navbarContainer.appendChild(imgElement)
      }
      
      imgElement.src = imageUrl
      imgElement.style.display = 'block'
      
      if (initialsElement) {
        initialsElement.style.display = 'none'
      }
    } else {
      // Show initials, hide image
      const imgElement = navbarContainer.querySelector('[data-navbar-profile-image]')
      let initialsElement = navbarContainer.querySelector('[data-navbar-profile-initials]')
      
      if (imgElement) {
        imgElement.style.display = 'none'
      }
      
      if (!initialsElement) {
        // Create initials element if it doesn't exist
        initialsElement = document.createElement('span')
        initialsElement.className = "text-white font-semibold text-xs"
        initialsElement.setAttribute('data-navbar-profile-initials', '')
        navbarContainer.appendChild(initialsElement)
      }
      
      initialsElement.textContent = getInitials(userName)
      initialsElement.style.display = 'block'
    }
  }

  updateProfileImage(imageUrl) {
    // Get or create the img element
    let imgElement = this.profileImageTarget
    
    // If img doesn't exist, create it
    if (!imgElement) {
      imgElement = document.createElement('img')
      imgElement.className = "w-full h-full object-cover"
      imgElement.setAttribute('data-settings-target', 'profileImage')
      imgElement.setAttribute('alt', 'Profile image')
      this.profileImageContainerTarget.appendChild(imgElement)
    }
    
    // Set the image source and show it
    imgElement.src = imageUrl
    imgElement.classList.remove('hidden')
    
    // Hide the initials span if it exists
    if (this.hasProfileInitialsTarget) {
      this.profileInitialsTarget.classList.add('hidden')
    }
  }

  exitEditMode(fieldType) {
    const display = this[`${fieldType}DisplayTarget`]
    const hasInput = this[`has${fieldType.charAt(0).toUpperCase() + fieldType.slice(1)}InputTarget`]
    
    if (!hasInput) return
    
    const input = this[`${fieldType}InputTarget`]
    
    // If input is visible (in edit mode), switch back to view mode
    if (!input.classList.contains('hidden')) {
      display.classList.remove('hidden')
      input.classList.add('hidden')
    }
  }

  discardChanges() {
    // Reset form inputs to original values
    if (this.hasNameInputTarget) {
      this.nameInputTarget.value = this.nameDisplayTarget.textContent.trim()
    }
    if (this.hasEmailInputTarget) {
      this.emailInputTarget.value = this.emailDisplayTarget.textContent.trim()
    }
    
    // Reset image removal flag
    if (this.hasRemoveImageFlagTarget) {
      this.removeImageFlagTarget.value = '0'
    }
    
    // Clear file input
    if (this.hasImageInputTarget) {
      this.imageInputTarget.value = ''
    }
    
    // Restore original image state
    if (this.initialImageUrl && this.initialImageVisible) {
      // Restore original image
      if (this.hasProfileImageTarget) {
        this.profileImageTarget.src = this.initialImageUrl
        this.profileImageTarget.classList.remove('hidden')
      }
      // Hide initials if they were shown
      if (this.hasProfileInitialsTarget) {
        this.profileInitialsTarget.classList.add('hidden')
      }
    } else {
      // No image was there originally - show initials
      if (this.hasProfileImageTarget) {
        this.profileImageTarget.classList.add('hidden')
        this.profileImageTarget.src = ''
      }
      if (this.hasProfileInitialsTarget && this.initialInitialsVisible) {
        this.profileInitialsTarget.classList.remove('hidden')
      }
    }
    
    // Exit edit mode for all fields
    this.exitEditMode('name')
    this.exitEditMode('email')
  }

  showMessage(message, type = 'success') {
    this.dispatchToast(message, type)
  }

  dispatchToast(message, type = 'success') {
    const bgColor = type === 'success' 
      ? 'bg-[#FFFFFF] border-[#E3E3E3] border-l-4 border-l-[#5C3984]'
      : 'bg-[#FFFFFF] border-[#E3E3E3] border-l-4 border-l-red-500';
    
    const icon = type === 'success'
      ? '<svg class="w-5 h-5 text-[#5C3984]" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/></svg>'
      : '<svg class="w-5 h-5 text-red-500" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"/></svg>';

    const notificationHtml = `
      <div 
        data-toast-target="notification"
        class="${bgColor} rounded-lg shadow-lg p-4 flex items-start gap-3 transform opacity-0 translate-x-full transition ease-out duration-300"
      >
        ${icon}
        <div class="flex-1 text-sm text-[#0D1120] font-medium">
          ${message}
        </div>
        <button 
          data-action="click->toast#close"
          class="text-gray-400 hover:text-gray-600 transition-colors"
        >
          <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd"/>
          </svg>
        </button>
      </div>
    `;

    // Dispatch custom event for toast controller to handle
    const event = new CustomEvent('toast:show', {
      detail: { notificationHtml },
      bubbles: true
    });
    document.dispatchEvent(event);
  }


  openImagePicker() {
    if (this.hasImageInputTarget) {
      this.imageInputTarget.click()
    }
  }

  handleProfileImageUpload(event) {
    // Reset the remove flag when a new image is selected
    if (this.hasRemoveImageFlagTarget) {
      this.removeImageFlagTarget.value = '0'
    }
    
    const file = event.target.files[0]
    if (file) {
      // Create object URL for preview
      const imageUrl = URL.createObjectURL(file)
      
      // Get or create the img element
      let imgElement = this.profileImageTarget
      
      // If img doesn't exist, create it
      if (!imgElement) {
        imgElement = document.createElement('img')
        imgElement.className = "w-full h-full object-cover"
        imgElement.setAttribute('data-settings-target', 'profileImage')
        imgElement.setAttribute('alt', 'Profile image')
        this.profileImageContainerTarget.appendChild(imgElement)
      }
      
      // Set the image source and show it
      imgElement.src = imageUrl
      imgElement.classList.remove('hidden')
      
      // Hide the initials span if it exists
      if (this.hasProfileInitialsTarget) {
        this.profileInitialsTarget.classList.add('hidden')
      }
    }
  }

  removeImage() {
    // Set the remove flag
    if (this.hasRemoveImageFlagTarget) {
      this.removeImageFlagTarget.value = '1'
    }
    
    // Clear the file input
    if (this.hasImageInputTarget) {
      this.imageInputTarget.value = ''
    }
    
    // Hide the image
    if (this.hasProfileImageTarget) {
      this.profileImageTarget.classList.add('hidden')
      this.profileImageTarget.src = ''
    }
    
    // Show the initials
    if (this.hasProfileInitialsTarget) {
      this.profileInitialsTarget.classList.remove('hidden')
    }
  }
}