import { Controller } from "@hotwired/stimulus"

// Level 0 → Level 1 → Level 2, each list narrowed by the one above it, so a
// procedure can only be filed under a level-2 process that really sits in
// the chosen band. The level-2 select is the field that is saved.
//
//   <div data-controller="process-picker" data-process-picker-processes-value='[{"id":..,"parentId":..,"level":1,"category":"core","label":".."}]'>
//     <select data-process-picker-target="band">…</select>
//     <select data-process-picker-target="level1"></select>
//     <select name="pp_record[pp_process_id]" data-process-picker-target="level2"></select>
//   </div>
export default class extends Controller {
  static targets = ["band", "level1", "level2"]
  static values = {
    processes: Array,
    selected: String,
    blankLabel: String
  }

  connect() {
    this.preselect()
    this.fillLevel1(this.level1Target.dataset.keep)
    this.fillLevel2(this.level2Target.dataset.keep)
  }

  bandChanged() {
    this.fillLevel1()
    this.fillLevel2()
  }

  level1Changed() {
    this.fillLevel2()
  }

  // On edit, walk up from the saved level-2 process to set the parents.
  preselect() {
    const saved = this.processesValue.find((p) => p.id === this.selectedValue)
    if (!saved) return
    const parent = this.processesValue.find((p) => p.id === saved.parentId)
    this.bandTarget.value = saved.category
    this.level1Target.dataset.keep = parent ? parent.id : ""
    this.level2Target.dataset.keep = saved.id
  }

  fillLevel1(keep = "") {
    const band = this.bandTarget.value
    const options = this.processesValue.filter((p) => p.level === 1 && (!band || p.category === band))
    this.render(this.level1Target, options, keep)
  }

  fillLevel2(keep = "") {
    const parentId = this.level1Target.value
    const options = parentId ? this.processesValue.filter((p) => p.level === 2 && p.parentId === parentId) : []
    this.render(this.level2Target, options, keep)
  }

  render(select, options, keep) {
    select.innerHTML = ""
    const blank = document.createElement("option")
    blank.value = ""
    blank.textContent = this.blankLabelValue
    select.appendChild(blank)
    options.forEach((p) => {
      const option = document.createElement("option")
      option.value = p.id
      option.textContent = p.label
      if (p.id === keep) option.selected = true
      select.appendChild(option)
    })
    select.disabled = options.length === 0
  }
}
