from datetime import timezone
from io import BytesIO

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas

from app.billing.models import Invoice
from app.users.models import User

SELLER_NAME = "Whiskr"
SELLER_ADDRESS = ["123 Demo Street", "Sample City, 000000", "support@whiskr.example"]


def _date(dt) -> str:
    dt = dt.replace(tzinfo=timezone.utc) if dt.tzinfo is None else dt
    return dt.strftime("%d %b %Y")  # shown in UTC


def build_invoice_pdf(inv: Invoice, user: User | None, plan_name: str, refunded: bool) -> bytes:
    buf = BytesIO()
    c = canvas.Canvas(buf, pagesize=A4)
    width, height = A4
    left, right = 50, width - 50
    y = height - 60

    # Header
    c.setFont("Helvetica-Bold", 24)
    c.drawString(left, y, SELLER_NAME)
    c.setFont("Helvetica-Bold", 20)
    c.drawRightString(right, y, "INVOICE")
    c.setFont("Helvetica", 10)
    c.setFillColor(colors.grey)
    for line in SELLER_ADDRESS:
        y -= 14
        c.drawString(left, y, line)
    c.setFillColor(colors.black)

    # Invoice facts (right column)
    ry = height - 80
    for label, value in [
        ("Invoice no", inv.invoice_no),
        ("Date paid", _date(inv.paid_at)),
        ("Payment id", inv.payment_id or "-"),
        ("Order id", inv.order_id),
    ]:
        c.setFont("Helvetica", 10)
        c.setFillColor(colors.grey)
        c.drawRightString(right - 150, ry, label)
        c.setFillColor(colors.black)
        c.drawRightString(right, ry, value)
        ry -= 14

    # Bill to
    y = height - 190
    c.setFont("Helvetica-Bold", 11)
    c.drawString(left, y, "Bill to")
    c.setFont("Helvetica", 10)
    name = f"{user.first_name} {user.last_name}" if user else inv.user_id
    c.drawString(left, y - 16, name)
    if user:
        c.drawString(left, y - 30, user.email)

    # Table
    ty = y - 80
    c.setFillColor(colors.HexColor("#F1F1F5"))
    c.rect(left, ty - 6, right - left, 24, stroke=0, fill=1)
    c.setFillColor(colors.black)
    c.setFont("Helvetica-Bold", 10)
    c.drawString(left + 8, ty + 2, "Description")
    c.drawString(left + 260, ty + 2, "Valid from")
    c.drawString(left + 340, ty + 2, "Valid till")
    c.drawRightString(right - 8, ty + 2, "Amount")

    ty -= 28
    c.setFont("Helvetica", 10)
    c.drawString(left + 8, ty, f"{plan_name} plan subscription")
    c.drawString(left + 260, ty, _date(inv.paid_at))
    c.drawString(left + 340, ty, _date(inv.valid_until))
    amount = f"Rs {inv.amount / 100:,.2f}"
    c.drawRightString(right - 8, ty, amount)
    c.line(left, ty - 12, right, ty - 12)

    # Total
    ty -= 36
    c.setFont("Helvetica-Bold", 12)
    c.drawRightString(right - 120, ty, "Total")
    c.drawRightString(right - 8, ty, amount)

    # Refund stamp
    if refunded:
        c.saveState()
        c.translate(width / 2, height / 2 - 40)
        c.rotate(25)
        c.setStrokeColor(colors.HexColor("#C62828"))
        c.setFillColor(colors.HexColor("#C62828"))
        c.setLineWidth(4)
        c.roundRect(-110, -30, 220, 60, 8, stroke=1, fill=0)
        c.setFont("Helvetica-Bold", 34)
        c.drawCentredString(0, -12, "REFUNDED")
        c.restoreState()

    # Footer
    c.setFont("Helvetica", 9)
    c.setFillColor(colors.grey)
    c.drawString(left, 60, "Test mode invoice. No real money was charged. No tax is applied.")
    c.drawString(left, 46, "Dates are shown in UTC.")
    c.showPage()
    c.save()
    return buf.getvalue()
