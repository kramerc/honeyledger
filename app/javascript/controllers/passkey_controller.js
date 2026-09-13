import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Drives both WebAuthn ceremonies against the app's JSON endpoints:
// `register` enrols a new passkey (settings page) and `authenticate` logs in
// with one (login page). Relies on the browser's own JSON helpers, so there is
// no client-side base64 handling; browsers without them see nothing.
export default class extends Controller {
  static targets = ["form", "nickname", "error", "unsupported", "button"]
  static values = { optionsUrl: String, submitUrl: String }

  connect() {
    if (this.supported) return

    if (this.hasFormTarget) this.formTarget.hidden = true
    if (this.hasUnsupportedTarget) this.unsupportedTarget.hidden = false
  }

  // Bound to the enrolment form's submit, so Enter in the name field works.
  async register(event) {
    event?.preventDefault()

    await this.run(async () => {
      const options = await this.post(this.optionsUrlValue)
      const publicKey = PublicKeyCredential.parseCreationOptionsFromJSON(options)
      const credential = await navigator.credentials.create({ publicKey })
      const nickname = this.hasNicknameTarget ? this.nicknameTarget.value : ""

      return this.post(this.submitUrlValue, { nickname, credential: credential.toJSON() })
    }, "Could not add the passkey.")
  }

  async authenticate(event) {
    event?.preventDefault()

    await this.run(async () => {
      const options = await this.post(this.optionsUrlValue)
      const publicKey = PublicKeyCredential.parseRequestOptionsFromJSON(options)
      const credential = await navigator.credentials.get({ publicKey })

      return this.post(this.submitUrlValue, { credential: credential.toJSON() })
    }, "Passkey sign-in failed.")
  }

  get supported() {
    return typeof window.PublicKeyCredential === "function" &&
      typeof PublicKeyCredential.parseCreationOptionsFromJSON === "function" &&
      typeof PublicKeyCredential.parseRequestOptionsFromJSON === "function"
  }

  async run(ceremony, failureMessage) {
    if (this.busy) return

    this.hideError()
    this.setBusy(true)

    try {
      const result = await ceremony()
      Turbo.visit(result.redirect_url)
    } catch (error) {
      // NotAllowedError is the browser reporting that the person dismissed the prompt.
      if (error.name !== "NotAllowedError") {
        this.showError(error instanceof RequestError ? error.message : failureMessage)
      }
    } finally {
      this.setBusy(false)
    }
  }

  // The browser's passkey prompt can take a moment to appear, so the button
  // shows that something is happening and refuses a second click meanwhile.
  setBusy(busy) {
    this.busy = busy
    if (!this.hasButtonTarget) return

    const button = this.buttonTarget
    if (busy) {
      button.dataset.idleLabel = button.textContent
      button.textContent = button.dataset.busyLabel || "Waiting for your device…"
      button.disabled = true
      button.setAttribute("aria-busy", "true")
    } else {
      button.textContent = button.dataset.idleLabel || button.textContent
      button.disabled = false
      button.removeAttribute("aria-busy")
    }
  }

  async post(url, body = {}) {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
      },
      credentials: "same-origin",
      body: JSON.stringify(body)
    })

    if (!response.ok) throw new RequestError(await this.describeFailure(response))

    return response.json()
  }

  async describeFailure(response) {
    if (response.status === 403) return "Confirm your password before adding a passkey."

    try {
      const body = await response.json()
      if (body.error) return body.error
    } catch {
      // Not a JSON body; fall through to the generic message.
    }

    return "Something went wrong. Please try again."
  }

  showError(message) {
    if (!this.hasErrorTarget) return

    this.errorTarget.textContent = message
    this.errorTarget.hidden = false
  }

  hideError() {
    if (this.hasErrorTarget) this.errorTarget.hidden = true
  }
}

class RequestError extends Error {}
