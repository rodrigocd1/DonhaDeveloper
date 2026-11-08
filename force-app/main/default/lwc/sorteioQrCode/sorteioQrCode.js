import { LightningElement, api } from "lwc";
import { loadScript } from "lightning/platformResourceLoader";
import QRCODE_GENERATOR from "@salesforce/resourceUrl/qrcodeGenerator";

const TAMANHO_CELULA = 8;
const MARGEM = 2;

export default class SorteioQrCode extends LightningElement {
  @api link;
  imagem;

  async connectedCallback() {
    try {
      await loadScript(this, QRCODE_GENERATOR);
      const qr = window.qrcode(0, "M");
      qr.addData(this.link);
      qr.make();
      this.imagem = qr.createDataURL(TAMANHO_CELULA, MARGEM);
    } catch {
      this.imagem = undefined;
    }
  }
}