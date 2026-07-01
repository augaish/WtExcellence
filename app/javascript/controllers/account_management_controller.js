import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "errorContainer"]

  connect() {
    // Initialize modals if they exist
    this.userModal = document.getElementById("addUserModal")
    this.companyModal = document.getElementById("addCompanyModal")
    this.permissionsModal = document.getElementById("permissionsModal")
    this.changePasswordModal = document.getElementById("changePasswordModal")
    this.changeRoleModal = document.getElementById("changeRoleModal")

    // Handle permissions form submission
    const permissionsForm = document.getElementById("permissionsForm")
    if (permissionsForm) {
      permissionsForm.addEventListener("submit", (event) => {
        event.preventDefault()
        this.submitPermissionsForm(event)
      })
    }

    // Handle change password form submission
    const changePasswordForm = document.getElementById("changePasswordForm")
    if (changePasswordForm) {
      changePasswordForm.addEventListener("submit", (event) => {
        event.preventDefault()
        this.submitChangePasswordForm(event)
      })
    }

    // Handle change role form submission
    const changeRoleForm = document.getElementById("changeRoleForm")
    if (changeRoleForm) {
      changeRoleForm.addEventListener("submit", (event) => {
        event.preventDefault()
        this.submitChangeRoleForm(event)
      })
    }
  }

  openAddUserModal(event) {
    event.preventDefault()
    if (this.userModal) {
      // If a company-id was passed (e.g. from company profile), preselect it
      const companyId = event.currentTarget?.dataset?.companyId
      if (companyId) {
        const companyField = document.getElementById("companyField")
        const companySelect = document.getElementById("companySelect")
        if (companyField) {
          // Check if Choices.js controller is attached to the wrapper
          const choicesController = this.application.getControllerForElementAndIdentifier(companyField, 'choices-select')
          if (choicesController && choicesController.choicesInstance) {
            choicesController.choicesInstance.setChoiceByValue(String(companyId))
          } else if (companySelect) {
            companySelect.value = companyId
          }
        }
      }

      this.userModal.showModal()
    }
  }

  closeAddUserModal(event) {
    event?.preventDefault()
    if (this.userModal) {
      this.userModal.close()
      this.clearForm()
    }
  }

  openAddCompanyModal(event) {
    event.preventDefault()
    if (this.companyModal) {
      this.companyModal.showModal()
    }
  }

  closeAddCompanyModal(event) {
    event?.preventDefault()
    if (this.companyModal) {
      this.companyModal.close()
      this.clearCompanyForm()
    }
  }

  submitInvitationForm(event) {
    const form = event.target
    const formData = new FormData(form)
    const errorContainer = document.getElementById("invitationErrors")

    // Clear previous errors
    if (errorContainer) {
      errorContainer.classList.add("hidden")
      errorContainer.textContent = ""
    }

    // Basic client-side validation
    const name = formData.get("name")
    const email = formData.get("email")
    const globalRole = formData.get("role")
    const companyId = formData.get("company_id")
    const companyRole = formData.get("company_role")
    const isDelegatedAdmin = globalRole === "delegated_admin"

    // For delegated admins, company and company role are not required
    if (!name || !email) {
      event.preventDefault()
      this.showError("Please fill in all required fields.")
      return
    }

    // Company and company role are required only for non-delegated admins
    if (!isDelegatedAdmin && (!companyId || !companyRole)) {
      event.preventDefault()
      this.showError("Please fill in all required fields.")
      return
    }

    // Email validation
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
    if (!emailRegex.test(email)) {
      event.preventDefault()
      this.showError("Please enter a valid email address.")
      return
    }

    // If validation passes, let the form submit normally
  }

  showError(message) {
    const errorContainer = document.getElementById("invitationErrors")
    if (errorContainer) {
      errorContainer.textContent = message
      errorContainer.classList.remove("hidden")
    }
  }

  togglePermissionsSection(event) {
    const roleSelect = event.target
    const permissionsSection = document.getElementById("permissionsSection")
    const companyField = document.getElementById("companyField")
    const companySelect = document.getElementById("companySelect")
    const companyRoleField = document.getElementById("companyRoleField")
    const companyRoleSelect = document.getElementById("companyRoleSelect")

    if (roleSelect.value === "delegated_admin") {
      // Show permissions section
      if (permissionsSection) {
        permissionsSection.classList.remove("hidden")
      }

      // Hide company and company role fields for delegated admins
      if (companyField) {
        companyField.classList.add("hidden")
        if (companySelect) {
          companySelect.removeAttribute("required")
        }
        // Reset via Choices.js if available
        const companyCtrl = this.application.getControllerForElementAndIdentifier(companyField, 'choices-select')
        if (companyCtrl) {
          companyCtrl.reset()
        } else if (companySelect) {
          companySelect.value = ""
        }
      }
      if (companyRoleField) {
        companyRoleField.classList.add("hidden")
        if (companyRoleSelect) {
          companyRoleSelect.removeAttribute("required")
        }
        // Reset via Choices.js if available
        const roleCtrl = this.application.getControllerForElementAndIdentifier(companyRoleField, 'choices-select')
        if (roleCtrl) {
          roleCtrl.reset()
        } else if (companyRoleSelect) {
          companyRoleSelect.value = ""
        }
      }
    } else {
      // Hide permissions section
      if (permissionsSection) {
        permissionsSection.classList.add("hidden")
        // Uncheck all permission checkboxes
        const checkboxes = permissionsSection.querySelectorAll('input[type="checkbox"]')
        checkboxes.forEach(checkbox => checkbox.checked = false)
      }

      // Show company and company role fields for regular users
      if (companyField) {
        companyField.classList.remove("hidden")
        if (companySelect) {
          companySelect.setAttribute("required", "required")
        }
      }
      if (companyRoleField) {
        companyRoleField.classList.remove("hidden")
        if (companyRoleSelect) {
          companyRoleSelect.setAttribute("required", "required")
        }
      }
    }
  }

  openPermissionsModal(event) {
    event.preventDefault()
    const button = event.currentTarget
    const userId = button.dataset.userId
    const userName = button.dataset.userName
    const userPermissions = JSON.parse(button.dataset.userPermissions || "[]")

    if (this.permissionsModal) {
      // Set user info
      document.getElementById("permissionsUserId").value = userId
      document.getElementById("permissionsModalUserName").textContent = `Manage permissions for ${userName}`

      // Set checkboxes based on current permissions
      const checkboxes = this.permissionsModal.querySelectorAll('.permission-checkbox')
      checkboxes.forEach(checkbox => {
        checkbox.checked = userPermissions.includes(checkbox.value)
      })

      // Clear errors
      const errorContainer = document.getElementById("permissionsErrors")
      if (errorContainer) {
        errorContainer.classList.add("hidden")
        errorContainer.textContent = ""
      }

      this.permissionsModal.showModal()
    }
  }

  closePermissionsModal(event) {
    event?.preventDefault()
    if (this.permissionsModal) {
      this.permissionsModal.close()
      const form = document.getElementById("permissionsForm")
      if (form) {
        form.reset()
      }
    }
  }

  async submitPermissionsForm(event) {
    event.preventDefault()
    const form = event.target
    const formData = new FormData(form)
    const userId = formData.get("user_id")
    const permissions = formData.getAll("permissions[]")

    const errorContainer = document.getElementById("permissionsErrors")

    try {
      const response = await fetch(`/dashboard/account_management/users/${userId}/permissions`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({ permissions: permissions })
      })

      const data = await response.json()

      if (data.success) {
        // Show success notification
        if (data.notification_html) {
          const notificationsContainer = document.getElementById("notifications")
          if (notificationsContainer) {
            notificationsContainer.insertAdjacentHTML("beforeend", data.notification_html)
            const toast = notificationsContainer.lastElementChild
            setTimeout(() => {
              toast?.remove()
            }, 5000)
          }
        }

        // Close modal
        this.closePermissionsModal()

        // Reload page to reflect changes
        window.location.reload()
      } else {
        // Show error
        if (errorContainer) {
          errorContainer.textContent = data.message || "Failed to update permissions."
          errorContainer.classList.remove("hidden")
        }
      }
    } catch (error) {
      console.error("Error updating permissions:", error)
      if (errorContainer) {
        errorContainer.textContent = "An error occurred while updating permissions."
        errorContainer.classList.remove("hidden")
      }
    }
  }

  clearForm() {
    const form = document.querySelector("#addUserModal form")
    if (form) {
      form.reset()
    }

    // Reset Choices.js company select if present
    const companyField = document.getElementById("companyField")
    if (companyField) {
      const choicesController = this.application.getControllerForElementAndIdentifier(companyField, 'choices-select')
      if (choicesController) {
        choicesController.reset()
      }
    }

    // Reset Choices.js company role select if present
    const companyRoleField = document.getElementById("companyRoleField")
    if (companyRoleField) {
      const roleController = this.application.getControllerForElementAndIdentifier(companyRoleField, 'choices-select')
      if (roleController) {
        roleController.reset()
      }
    }

    // Reset Choices.js global role select if present
    const globalRoleWrapper = document.querySelector("#addUserModal [data-controller='choices-select']:has(#globalRoleSelect)")
    if (globalRoleWrapper) {
      const globalRoleController = this.application.getControllerForElementAndIdentifier(globalRoleWrapper, 'choices-select')
      if (globalRoleController) {
        globalRoleController.reset()
      }
    }

    // Hide permissions section
    const permissionsSection = document.getElementById("permissionsSection")
    if (permissionsSection) {
      permissionsSection.classList.add("hidden")
    }

    const errorContainer = document.getElementById("invitationErrors")
    if (errorContainer) {
      errorContainer.classList.add("hidden")
      errorContainer.textContent = ""
    }
  }

  submitCompanyForm(event) {
    const form = event.target
    const formData = new FormData(form)
    const errorContainer = document.getElementById("companyErrors")

    // Clear previous errors
    if (errorContainer) {
      errorContainer.classList.add("hidden")
      errorContainer.textContent = ""
    }

    // Basic client-side validation
    const name = formData.get("company[name]")
    const licenseSeats = formData.get("company[license_seats]")
    const credits = formData.get("company[credits]")

    if (!name || !licenseSeats || !credits) {
      event.preventDefault()
      this.showCompanyError("Please fill in all required fields.")
      return
    }

    // Validate numeric fields
    if (parseInt(licenseSeats) < 0) {
      event.preventDefault()
      this.showCompanyError("License seats must be 0 or greater.")
      return
    }

    if (parseInt(credits) < 0) {
      event.preventDefault()
      this.showCompanyError("Credits must be 0 or greater.")
      return
    }

    // If validation passes, let the form submit normally
  }

  showCompanyError(message) {
    const errorContainer = document.getElementById("companyErrors")
    if (errorContainer) {
      errorContainer.textContent = message
      errorContainer.classList.remove("hidden")
    }
  }

  clearCompanyForm() {
    const form = document.querySelector("#addCompanyModal form")
    if (form) {
      form.reset()
    }

    const errorContainer = document.getElementById("companyErrors")
    if (errorContainer) {
      errorContainer.classList.add("hidden")
      errorContainer.textContent = ""
    }
  }

  // Handle modal backdrop clicks
  // Do not close modals on backdrop click; users must use the close button
  modalClick(_event) {
    // Intentionally no-op: backdrop click closing is disabled app-wide via dialog-no-backdrop-close
  }

  editLicenseSeats(event) {
    const companyId = event.currentTarget.dataset.companyId
    const displayEl = document.getElementById(`license-seats-display-${companyId}`)
    const inputEl = document.getElementById(`license-seats-input-${companyId}`)
    const editBtn = event.currentTarget
    const saveBtn = document.getElementById(`license-seats-save-${companyId}`)
    const cancelBtn = document.getElementById(`license-seats-cancel-${companyId}`)

    if (displayEl && inputEl && saveBtn && cancelBtn) {
      displayEl.classList.add("hidden")
      editBtn.classList.add("hidden")
      inputEl.classList.remove("hidden")
      saveBtn.classList.remove("hidden")
      cancelBtn.classList.remove("hidden")
      inputEl.focus()
      inputEl.select()
    }
  }

  saveLicenseSeats(event) {
    const companyId = event.currentTarget.dataset.companyId
    const inputEl = document.getElementById(`license-seats-input-${companyId}`)
    const displayEl = document.getElementById(`license-seats-display-${companyId}`)
    const editBtn = document.querySelector(`[data-company-id="${companyId}"][data-action*="editLicenseSeats"]`)
    const saveBtn = event.currentTarget
    const cancelBtn = document.getElementById(`license-seats-cancel-${companyId}`)

    if (!inputEl || !displayEl) return

    const licenseSeats = parseInt(inputEl.value)
    const currentUsers = parseInt(inputEl.dataset.currentUsers) || 0

    if (isNaN(licenseSeats) || licenseSeats < 0) {
      this.dispatchToast("License seats must be 0 or greater.", "error")
      return
    }

    if (licenseSeats < currentUsers) {
      this.dispatchToast(`License seats cannot be less than current user count (${currentUsers} users).`, "error")
      return
    }

    // Disable buttons during save
    saveBtn.disabled = true
    cancelBtn.disabled = true
    inputEl.disabled = true

    const url = `/dashboard/account_management/companies/${companyId}/license_seats`
    const csrfToken = document.querySelector('meta[name="csrf-token"]').content

    fetch(url, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken,
        "Accept": "application/json"
      },
      body: JSON.stringify({ license_seats: licenseSeats })
    })
      .then(response => response.json())
      .then(data => {
        if (data.success) {
          displayEl.textContent = data.license_seats
          inputEl.value = data.license_seats
          // Min should always be current user count
          inputEl.min = currentUsers

          // Update available seats wherever shown for this company
          const available = Math.max(data.license_seats - currentUsers, 0)
          const availableEls = document.querySelectorAll(`.license-seats-available[data-company-id="${companyId}"]`)
          availableEls.forEach(el => {
            el.textContent = available
          })

          // Show success toast notification
          this.dispatchToast(data.message || "License seats updated successfully", "success")
        } else {
          // Show error toast notification
          this.dispatchToast(data.message || "Failed to update license seats", "error")
          inputEl.value = displayEl.textContent // Reset to original value
        }
      })
      .catch(error => {
        console.error("Error:", error)
        this.dispatchToast("An error occurred while updating license seats", "error")
        inputEl.value = displayEl.textContent // Reset to original value
      })
      .finally(() => {
        // Hide input, show display
        displayEl.classList.remove("hidden")
        editBtn.classList.remove("hidden")
        inputEl.classList.add("hidden")
        saveBtn.classList.add("hidden")
        cancelBtn.classList.add("hidden")

        // Re-enable buttons
        saveBtn.disabled = false
        cancelBtn.disabled = false
        inputEl.disabled = false
      })
  }

  cancelLicenseSeatsEdit(event) {
    const companyId = event.currentTarget.dataset.companyId
    const displayEl = document.getElementById(`license-seats-display-${companyId}`)
    const inputEl = document.getElementById(`license-seats-input-${companyId}`)
    const editBtn = document.querySelector(`[data-company-id="${companyId}"][data-action*="editLicenseSeats"]`)
    const saveBtn = document.getElementById(`license-seats-save-${companyId}`)
    const cancelBtn = event.currentTarget

    if (displayEl && inputEl && editBtn && saveBtn && cancelBtn) {
      // Reset input value to display value
      inputEl.value = displayEl.textContent

      // Hide input, show display
      displayEl.classList.remove("hidden")
      editBtn.classList.remove("hidden")
      inputEl.classList.add("hidden")
      saveBtn.classList.add("hidden")
      cancelBtn.classList.add("hidden")
    }
  }

  openChangePasswordModal(event) {
    event.preventDefault()
    const button = event.currentTarget
    const userId = button.dataset.userId
    const userName = button.dataset.userName

    if (this.changePasswordModal) {
      // Set user info
      document.getElementById("changePasswordUserId").value = userId
      document.getElementById("changePasswordUserName").textContent = `Change password for ${userName}`

      // Clear form and errors
      const form = document.getElementById("changePasswordForm")
      if (form) {
        form.reset()
      }

      const errorContainer = document.getElementById("changePasswordErrors")
      if (errorContainer) {
        errorContainer.classList.add("hidden")
        errorContainer.textContent = ""
      }

      const successContainer = document.getElementById("changePasswordSuccess")
      if (successContainer) {
        successContainer.classList.add("hidden")
        successContainer.textContent = ""
      }

      this.changePasswordModal.showModal()
    }
  }

  closeChangePasswordModal(event) {
    event?.preventDefault()
    if (this.changePasswordModal) {
      this.changePasswordModal.close()
      const form = document.getElementById("changePasswordForm")
      if (form) {
        form.reset()
      }
    }
  }

  async submitChangePasswordForm(event) {
    event.preventDefault()
    const form = event.target
    const formData = new FormData(form)
    const userId = formData.get("user_id")
    const password = formData.get("password")
    const passwordConfirmation = formData.get("password_confirmation")

    const errorContainer = document.getElementById("changePasswordErrors")
    const successContainer = document.getElementById("changePasswordSuccess")

    // Clear previous messages
    if (errorContainer) {
      errorContainer.classList.add("hidden")
      errorContainer.textContent = ""
    }
    if (successContainer) {
      successContainer.classList.add("hidden")
      successContainer.textContent = ""
    }

    // Validate passwords match
    if (password !== passwordConfirmation) {
      if (errorContainer) {
        errorContainer.textContent = "Passwords do not match."
        errorContainer.classList.remove("hidden")
      }
      return
    }

    // Validate password length
    if (password.length < 8) {
      if (errorContainer) {
        errorContainer.textContent = "Password must be at least 8 characters long."
        errorContainer.classList.remove("hidden")
      }
      return
    }

    try {
      const response = await fetch(`/dashboard/account_management/users/${userId}/change_password`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({
          password: password,
          password_confirmation: passwordConfirmation
        })
      })

      const data = await response.json()

      if (data.success) {
        // Show success message
        if (successContainer) {
          successContainer.textContent = data.message || "Password changed successfully."
          successContainer.classList.remove("hidden")
        }

        // Show toast notification
        this.dispatchToast(data.message || "Password changed successfully", "success")

        // Close modal after 1.5 seconds
        setTimeout(() => {
          this.closeChangePasswordModal()
        }, 1500)
      } else {
        // Show error
        if (errorContainer) {
          errorContainer.textContent = data.message || "Failed to change password."
          errorContainer.classList.remove("hidden")
        }
      }
    } catch (error) {
      console.error("Error changing password:", error)
      if (errorContainer) {
        errorContainer.textContent = "An error occurred while changing the password."
        errorContainer.classList.remove("hidden")
      }
    }
  }

  openChangeRoleModal(event) {
    event.preventDefault()
    const button = event.currentTarget
    const userId = button.dataset.userId
    const userName = button.dataset.userName
    const userRole = button.dataset.userRole || ""
    const companyRole = button.dataset.companyRole || ""
    const hasCompanyUser = button.dataset.hasCompanyUser === "true"

    if (this.changeRoleModal) {
      // Set user info
      document.getElementById("changeRoleUserId").value = userId
      document.getElementById("changeRoleHasCompanyUser").value = hasCompanyUser
      document.getElementById("changeRoleUserName").textContent = `Change role for ${userName}`

      // Set current global role display
      const currentGlobalRoleDisplay = document.getElementById("changeRoleCurrentGlobalRole")
      if (currentGlobalRoleDisplay) {
        const roleNames = {
          "super_admin": "Super Admin",
          "delegated_admin": "Delegated Admin",
          "viewer": "Viewer",
          "": "Regular User"
        }
        currentGlobalRoleDisplay.textContent = roleNames[userRole] || "Regular User"
      }

      // Set current global role in select
      const globalRoleWrapper = document.getElementById("changeRoleGlobalRoleWrapper")
      if (globalRoleWrapper) {
        const ctrl = this.application.getControllerForElementAndIdentifier(globalRoleWrapper, 'choices-select')
        if (ctrl && ctrl.choicesInstance) {
          ctrl.choicesInstance.setChoiceByValue(userRole)
        } else {
          const globalRoleSelect = document.getElementById("newGlobalRole")
          if (globalRoleSelect) globalRoleSelect.value = userRole
        }
      }

      // Handle company role section
      const companyRoleSection = document.getElementById("changeRoleCompanyRoleSection")
      const newCompanyRoleSection = document.getElementById("changeRoleNewCompanyRoleSection")

      if (hasCompanyUser) {
        // Show company role sections
        if (companyRoleSection) {
          companyRoleSection.style.display = "flex"
        }
        if (newCompanyRoleSection) {
          newCompanyRoleSection.style.display = "flex"
        }

        // Set current company role display
        const currentCompanyRoleDisplay = document.getElementById("changeRoleCurrentCompanyRole")
        if (currentCompanyRoleDisplay && companyRole) {
          const companyRoleNames = {
            "company_admin": "Company Admin",
            "company_quality_manager": "Quality Manager",
            "company_auditor": "Auditor",
            "company_contributor": "Contributor",
            "company_viewer": "Viewer"
          }
          currentCompanyRoleDisplay.textContent = companyRoleNames[companyRole] || companyRole.replace('company_', '').replace(/_/g, ' ').split(' ').map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(' ')
        }

        // Set current company role in select
        const companyRoleWrapper = document.getElementById("changeRoleNewCompanyRoleSection")
        if (companyRoleWrapper) {
          const ctrl = this.application.getControllerForElementAndIdentifier(companyRoleWrapper, 'choices-select')
          if (ctrl && ctrl.choicesInstance) {
            ctrl.choicesInstance.setChoiceByValue(companyRole)
          } else {
            const companyRoleSelect = document.getElementById("newCompanyRole")
            if (companyRoleSelect) companyRoleSelect.value = companyRole
          }
        }
      } else {
        // Hide company role sections
        if (companyRoleSection) {
          companyRoleSection.style.display = "none"
        }
        if (newCompanyRoleSection) {
          newCompanyRoleSection.style.display = "none"
        }
      }

      // Clear form and errors
      const errorContainer = document.getElementById("changeRoleErrors")
      if (errorContainer) {
        errorContainer.classList.add("hidden")
        errorContainer.textContent = ""
      }

      const successContainer = document.getElementById("changeRoleSuccess")
      if (successContainer) {
        successContainer.classList.add("hidden")
        successContainer.textContent = ""
      }

      this.changeRoleModal.showModal()
    }
  }

  closeChangeRoleModal(event) {
    event?.preventDefault()
    if (this.changeRoleModal) {
      this.changeRoleModal.close()
      const form = document.getElementById("changeRoleForm")
      if (form) {
        form.reset()
      }
    }
  }

  async submitChangeRoleForm(event) {
    event.preventDefault()
    const form = event.target
    const formData = new FormData(form)
    const userId = formData.get("user_id")
    const hasCompanyUser = formData.get("has_company_user") === "true"
    const newGlobalRole = formData.get("global_role")
    const newCompanyRole = formData.get("company_role")

    const errorContainer = document.getElementById("changeRoleErrors")
    const successContainer = document.getElementById("changeRoleSuccess")

    // Clear previous messages
    if (errorContainer) {
      errorContainer.classList.add("hidden")
      errorContainer.textContent = ""
    }
    if (successContainer) {
      successContainer.classList.add("hidden")
      successContainer.textContent = ""
    }

    // Validate company role if user has company
    if (hasCompanyUser && !newCompanyRole) {
      if (errorContainer) {
        errorContainer.textContent = "Please select a company role."
        errorContainer.classList.remove("hidden")
      }
      return
    }

    try {
      const response = await fetch(`/dashboard/account_management/users/${userId}/change_role`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({
          global_role: newGlobalRole,
          company_role: newCompanyRole
        })
      })

      const data = await response.json()

      if (data.success) {
        // Show success message
        if (successContainer) {
          successContainer.textContent = data.message || "Role changed successfully."
          successContainer.classList.remove("hidden")
        }

        // Show toast notification
        this.dispatchToast(data.message || "Role changed successfully", "success")

        // Close modal after 1.5 seconds
        setTimeout(() => {
          this.closeChangeRoleModal()
          // Reload page to reflect changes
          window.location.reload()
        }, 1500)
      } else {
        // Show error
        if (errorContainer) {
          errorContainer.textContent = data.message || "Failed to change role."
          errorContainer.classList.remove("hidden")
        }
      }
    } catch (error) {
      console.error("Error changing role:", error)
      if (errorContainer) {
        errorContainer.textContent = "An error occurred while changing the role."
        errorContainer.classList.remove("hidden")
      }
    }
  }

  updateCompanyStatus(event) {
    event.preventDefault()
    const link = event.currentTarget
    const url = new URL(link.href, window.location.origin)
    const pathParts = url.pathname.split('/')
    const companyId = pathParts[pathParts.length - 2] // Get company ID from path
    const newStatus = url.searchParams.get('status')

    if (!companyId || !newStatus) {
      this.dispatchToast("Invalid company or status", "error")
      return
    }

    // Disable the link and show loading state
    link.style.pointerEvents = "none"
    link.style.opacity = "0.6"
    link.style.cursor = "not-allowed"
    const originalText = link.textContent.trim()
    link.textContent = "..."
    link.disabled = true

    const apiUrl = `/dashboard/account_management/companies/${companyId}/status`
    const csrfToken = document.querySelector('meta[name="csrf-token"]').content

    fetch(apiUrl, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken,
        "Accept": "application/json"
      },
      body: JSON.stringify({ status: newStatus })
    })
      .then(response => response.json())
      .then(data => {
        if (data.success) {
          // Update status badge in companies table
          this.updateCompanyStatusUI(companyId, data.status, data.is_active)

          // Show success toast
          this.dispatchToast(data.message || "Company status updated successfully", "success")

          // Reload page after a short delay to reflect all changes
          setTimeout(() => {
            window.location.reload()
          }, 1000)
        } else {
          // Show error toast
          this.dispatchToast(data.message || "Failed to update company status", "error")

          // Re-enable the link
          this.resetCompanyStatusButton(link, originalText)
        }
      })
      .catch(error => {
        console.error("Error updating company status:", error)
        this.dispatchToast("An error occurred while updating company status", "error")

        // Re-enable the link
        this.resetCompanyStatusButton(link, originalText)
      })
  }

  resetCompanyStatusButton(link, originalText) {
    link.style.pointerEvents = "auto"
    link.style.opacity = "1"
    link.style.cursor = "pointer"
    link.textContent = originalText
    link.disabled = false
  }

  toggleTrustCenter(event) {
    event.preventDefault()
    const link = event.currentTarget
    const url = new URL(link.href, window.location.origin)
    const pathParts = url.pathname.split('/')
    const companyId = pathParts[pathParts.length - 2]

    if (!companyId) {
      this.dispatchToast("Invalid company", "error")
      return
    }

    link.style.pointerEvents = "none"
    link.style.opacity = "0.6"
    const originalText = link.textContent.trim()
    link.textContent = "..."

    const apiUrl = `/dashboard/account_management/companies/${companyId}/trust_center`
    const csrfToken = document.querySelector('meta[name="csrf-token"]').content

    fetch(apiUrl, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken,
        "Accept": "application/json"
      }
    })
      .then(response => response.json())
      .then(data => {
        if (data.success) {
          this.dispatchToast(data.message || "Trust Center updated", "success")
          setTimeout(() => window.location.reload(), 800)
        } else {
          this.dispatchToast(data.message || "Failed to update Trust Center", "error")
          link.style.pointerEvents = "auto"
          link.style.opacity = "1"
          link.textContent = originalText
        }
      })
      .catch(error => {
        console.error("Error toggling Trust Center:", error)
        this.dispatchToast("An error occurred while updating Trust Center", "error")
        link.style.pointerEvents = "auto"
        link.style.opacity = "1"
        link.textContent = originalText
      })
  }

  updateCompanyStatusUI(companyId, status, isActive) {
    // Update status badge in companies table
    const statusBadge = document.querySelector(`.status-badge-${companyId}`)
    if (statusBadge) {
      const statusText = status === "active" ? "Active" : "Pending"
      const badgeClass = status === "active" ? "bg-green-100 text-green-800" : "bg-yellow-100 text-yellow-800"
      statusBadge.textContent = statusText
      statusBadge.className = `px-2 inline-flex text-xs leading-5 font-semibold rounded-full ${badgeClass} status-badge-${companyId}`
    }

    // Update status in company detail page
    const detailStatusBadge = document.querySelector(`.company-status-badge`)
    if (detailStatusBadge) {
      const statusText = status === "active" ? "Active" : "Pending"
      const badgeClass = status === "active" ? "bg-green-100 text-green-800" : "bg-yellow-100 text-yellow-800"
      detailStatusBadge.textContent = statusText
      detailStatusBadge.className = `mt-2 inline-flex px-3 py-1 text-sm font-semibold rounded-full ${badgeClass} company-status-badge`
    }

    // Update activate/deactivate button text and href
    const statusButton = document.querySelector(`[data-company-status-button="${companyId}"]`)
    if (statusButton) {
      const baseUrl = statusButton.href.split('?')[0]
      if (status === "active") {
        statusButton.textContent = "Deactivate"
        statusButton.href = `${baseUrl}?status=pending`
        statusButton.className = statusButton.className.replace(/bg-\[#5C3984\]|bg-red-600/, "bg-red-600").replace(/hover:bg-\[#4A2F6B\]|hover:bg-red-700/, "hover:bg-red-700")
        statusButton.className = statusButton.className.replace(/text-\[#5C3984\]|text-red-600/, "text-red-600").replace(/hover:text-\[#4A2F6B\]|hover:text-red-700/, "hover:text-red-700")
      } else {
        statusButton.textContent = "Activate"
        statusButton.href = `${baseUrl}?status=active`
        statusButton.className = statusButton.className.replace(/bg-red-600|bg-\[#5C3984\]/, "bg-[#5C3984]").replace(/hover:bg-red-700|hover:bg-\[#4A2F6B\]/, "hover:bg-[#4A2F6B]")
        statusButton.className = statusButton.className.replace(/text-red-600|text-\[#5C3984\]/, "text-[#5C3984]").replace(/hover:text-red-700|hover:text-\[#4A2F6B\]/, "hover:text-[#4A2F6B]")
      }
    }
  }

  dispatchToast(notificationHtmlOrMessage, type = "success") {
    let notificationHtml = notificationHtmlOrMessage

    // If it's a plain message string, create notification HTML
    if (!notificationHtmlOrMessage || (typeof notificationHtmlOrMessage === "string" && !notificationHtmlOrMessage.includes("data-toast-target"))) {
      const bgColor = type === "success"
        ? "bg-[#FFFFFF] border-[#E3E3E3] border-l-4 border-l-[#5C3984]"
        : "bg-[#FFFFFF] border-[#E3E3E3] border-l-4 border-l-red-500"

      const icon = type === "success"
        ? '<svg class="w-5 h-5 text-[#5C3984]" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/></svg>'
        : '<svg class="w-5 h-5 text-red-500" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"/></svg>'

      notificationHtml = `
        <div 
          data-toast-target="notification"
          class="${bgColor} rounded-lg shadow-lg p-4 flex items-start gap-3 transform opacity-0 translate-x-full transition ease-out duration-300"
        >
          ${icon}
          <div class="flex-1 text-sm text-[#0D1120] font-medium">
            ${notificationHtmlOrMessage || "Operation completed"}
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
      `
    }

    // Dispatch custom event for toast controller to handle
    const event = new CustomEvent("toast:show", {
      detail: { notificationHtml },
      bubbles: true
    })
    document.dispatchEvent(event)
  }

}

