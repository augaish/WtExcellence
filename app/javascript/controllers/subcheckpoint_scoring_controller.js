import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["scoringType", "minScore", "maxScore", "minScoreContainer", "maxScoreContainer", "multipleChoiceSection", "minMaxSection"]

    connect() {
        this.updateDisplay()
    }

    scoringTypeChanged() {
        this.updateDisplay()
    }

    updateDisplay() {
        this.updatePercentageDisplay()
        this.updateMultipleChoiceDisplay()
    }

    updateMultipleChoiceDisplay() {
        const isMultipleChoice = this.scoringTypeTarget.value === "Multiple Choice"
        
        // Get all min/max sections (there are two - one for min, one for max)
        const minMaxSections = this.element.querySelectorAll('[data-subcheckpoint-scoring-target="minMaxSection"]')
        
        if (this.hasMultipleChoiceSectionTarget) {
            if (isMultipleChoice) {
                this.multipleChoiceSectionTarget.classList.remove("hidden")
                this.multipleChoiceSectionTarget.style.gridColumn = "5 / 7"
            } else {
                this.multipleChoiceSectionTarget.classList.add("hidden")
            }
        }
        
        // Hide/show min and max sections
        minMaxSections.forEach(section => {
            if (isMultipleChoice) {
                section.classList.add("hidden")
            } else {
                section.classList.remove("hidden")
            }
        })
    }

    updatePercentageDisplay() {
        const isPercentage = this.scoringTypeTarget.value === "Percentage"
        
        // Add or remove percentage indicator
        if (isPercentage) {
            // Add % symbol to min score
            if (this.hasMinScoreContainerTarget) {
                if (!this.minScoreContainerTarget.querySelector('.percentage-indicator')) {
                    const indicator = document.createElement('span')
                    indicator.className = 'percentage-indicator text-sm text-[#0D1120] pointer-events-none'
                    indicator.textContent = '%'
                    indicator.style.position = 'absolute'
                    indicator.style.right = '0.5rem'
                    indicator.style.top = '50%'
                    indicator.style.transform = 'translateY(-50%)'
                    this.minScoreContainerTarget.style.position = 'relative'
                    this.minScoreContainerTarget.appendChild(indicator)
                }
            }
            
            // Add % symbol to max score
            if (this.hasMaxScoreContainerTarget) {
                if (!this.maxScoreContainerTarget.querySelector('.percentage-indicator')) {
                    const indicator = document.createElement('span')
                    indicator.className = 'percentage-indicator text-sm text-[#0D1120] pointer-events-none'
                    indicator.textContent = '%'
                    indicator.style.position = 'absolute'
                    indicator.style.right = '0.5rem'
                    indicator.style.top = '50%'
                    indicator.style.transform = 'translateY(-50%)'
                    this.maxScoreContainerTarget.style.position = 'relative'
                    this.maxScoreContainerTarget.appendChild(indicator)
                }
            }
            
            // Add padding to inputs to make room for %
            if (this.hasMinScoreTarget) {
                this.minScoreTarget.style.paddingRight = '1.5rem'
            }
            if (this.hasMaxScoreTarget) {
                this.maxScoreTarget.style.paddingRight = '1.5rem'
            }
        } else {
            // Remove % symbols
            if (this.hasMinScoreContainerTarget) {
                const indicator = this.minScoreContainerTarget.querySelector('.percentage-indicator')
                if (indicator) {
                    indicator.remove()
                }
            }
            if (this.hasMaxScoreContainerTarget) {
                const indicator = this.maxScoreContainerTarget.querySelector('.percentage-indicator')
                if (indicator) {
                    indicator.remove()
                }
            }
            
            // Remove padding from inputs
            if (this.hasMinScoreTarget) {
                this.minScoreTarget.style.paddingRight = ''
            }
            if (this.hasMaxScoreTarget) {
                this.maxScoreTarget.style.paddingRight = ''
            }
        }
    }
}

