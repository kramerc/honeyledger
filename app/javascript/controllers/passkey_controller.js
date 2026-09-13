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
      this.showError(this.describeError(error, failureMessage))
    } finally {
      this.setBusy(false)
    }
  }

  // The WebAuthn API reports a fixed set of DOMException names; each gets a
  // plain sentence. Errors from our own endpoints arrive as RequestError with
  // their message already set.
  describeError(error, failureMessage) {
    if (error instanceof RequestError) return error.message

    switch (error.name) {
      case "NotAllowedError":
        return "The passkey prompt was cancelled or timed out. Nothing was changed."
      case "InvalidStateError":
        return "This device already has a passkey for your account."
      case "ConstraintError":
        return "This device cannot verify it is you. A screen lock, PIN, or biometric is required for passkeys."
      case "NotSupportedError":
        return "This device cannot create the kind of passkey the app asks for."
      case "SecurityError":
        return "This site's passkey settings do not match the address you are using."
      case "AbortError":
        return "The passkey request was interrupted. Please try again."
      case "TypeError":
        return "Could not reach the server. Check your connection and try again."
      default:
        return `${failureMessage} (${error.name || "unknown error"})`
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

  // Our endpoints explain refusals in a JSON `error` field; rate limiting
  // is the one response that carries no body.
  async describeFailure(response) {
    if (response.status === 429) return "Too many attempts. Please wait a few minutes and try again."

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
