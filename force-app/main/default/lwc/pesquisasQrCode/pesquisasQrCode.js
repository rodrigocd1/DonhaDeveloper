import { LightningElement, api } from "lwc";
import { loadScript } from "lightning/platformResourceLoader";
import qrcodeResource from "@salesforce/resourceUrl/qrcode";

export default class PesquisasQrCode extends LightningElement {
  @api value;
  @api alternativeText = "QR Code";

  imageUrl;
  errorMessage;
  libraryPromise;
  renderedValue;

  renderedCallback() {
    if (!this.value || this.renderedValue === this.value) {
      return;
    }
    if (!this.libraryPromise) {
      this.libraryPromise = loadScript(this, qrcodeResource);
    }
    this.libraryPromise
      .then(() => this.generateQrCode())
      .catch(() => {
        this.errorMessage = "QR Code indisponível. Use o botão de acesso.";
      });
  }

  generateQrCode() {
    if (typeof window.qrcode !== "function") {
      throw new Error("Biblioteca de QR Code indisponível.");
    }
    const generator = window.qrcode(0, "M");
    generator.addData(this.value);
    generator.make();
    this.imageUrl = generator.createDataURL(6, 8);
    this.renderedValue = this.value;
    this.errorMessage = undefined;
  }
}
