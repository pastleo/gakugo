import json
from anki.collection import Collection
from anki.notes import Note
from anki.decks import DeckId


def with_collection(path, fn):
    col = Collection(path)
    try:
        return fn(col)
    finally:
        col.close()


def ensure_deck(collection_path, deck_name):
    def _do(col):
        deck_id = col.decks.id(deck_name)
        return int(deck_id)

    return with_collection(collection_path, _do)


def list_decks(collection_path):
    def _do(col):
        return [deck["name"] for deck in col.decks.all()]

    return with_collection(collection_path, _do)


def ensure_model(collection_path, model_json):
    model_data = json.loads(model_json)

    def _do(col):
        existing = col.models.by_name(model_data["name"])

        if existing:
            updated = False
            existing_field_names = [f["name"] for f in existing["flds"]]
            for field_name in model_data["fields"]:
                if field_name not in existing_field_names:
                    col.models.addField(existing, col.models.new_field(field_name))
                    updated = True

            if "css" in model_data and model_data["css"] != existing.get("css", ""):
                existing["css"] = model_data["css"]
                updated = True

            if "templates" in model_data:
                existing_template_names = [t["name"] for t in existing["tmpls"]]
                for tmpl_data in model_data["templates"]:
                    if tmpl_data["name"] not in existing_template_names:
                        new_tmpl = col.models.new_template(tmpl_data["name"])
                        new_tmpl["qfmt"] = tmpl_data["qfmt"]
                        new_tmpl["afmt"] = tmpl_data["afmt"]
                        col.models.add_template(existing, new_tmpl)
                        updated = True
                    else:
                        for tmpl in existing["tmpls"]:
                            if tmpl["name"] == tmpl_data["name"]:
                                if (
                                    tmpl["qfmt"] != tmpl_data["qfmt"]
                                    or tmpl["afmt"] != tmpl_data["afmt"]
                                ):
                                    tmpl["qfmt"] = tmpl_data["qfmt"]
                                    tmpl["afmt"] = tmpl_data["afmt"]
                                    updated = True
                                break

            if updated:
                col.models.save(existing)

            return int(existing["id"])
        else:
            new_model = col.models.new(model_data["name"])

            for field_name in model_data["fields"]:
                col.models.addField(new_model, col.models.new_field(field_name))

            if "css" in model_data:
                new_model["css"] = model_data["css"]

            for tmpl_data in model_data.get("templates", []):
                tmpl = col.models.new_template(tmpl_data["name"])
                tmpl["qfmt"] = tmpl_data["qfmt"]
                tmpl["afmt"] = tmpl_data["afmt"]
                col.models.add_template(new_model, tmpl)

            col.models.add(new_model)
            return int(new_model["id"])

    return with_collection(collection_path, _do)


def list_models(collection_path):
    def _do(col):
        return [model["name"] for model in col.models.all()]

    return with_collection(collection_path, _do)


def add_note(collection_path, note_json):
    note_data = json.loads(note_json)

    def _do(col):
        model = col.models.by_name(note_data["model_name"])
        if not model:
            raise ValueError(f"Model not found: {note_data['model_name']}")

        deck_id = col.decks.id(note_data["deck_name"])

        note = Note(col, model)
        for field_name, value in note_data["fields"].items():
            if field_name in note:
                note[field_name] = value

        for tag in note_data.get("tags", []):
            note.tags.append(tag)

        col.add_note(note, DeckId(deck_id))
        return int(note.id)

    return with_collection(collection_path, _do)


def update_note(collection_path, note_json):
    note_data = json.loads(note_json)

    def _do(col):
        note = col.get_note(note_data["id"])

        for field_name, value in note_data["fields"].items():
            if field_name in note:
                note[field_name] = value

        note.tags = note_data.get("tags", [])

        col.update_note(note)

        if "deck_name" in note_data:
            deck_id = col.decks.id(note_data["deck_name"])
            card_ids = col.card_ids_of_note(note.id)
            if card_ids:
                col.set_deck(card_ids, deck_id)

    return with_collection(collection_path, _do)


def delete_note(collection_path, note_id):
    def _do(col):
        col.remove_notes([note_id])

    return with_collection(collection_path, _do)


def find_notes(collection_path, query):
    def _do(col):
        return [int(nid) for nid in col.find_notes(query)]

    return with_collection(collection_path, _do)


def get_note(collection_path, note_id):
    def _do(col):
        note = col.get_note(note_id)
        model = note.note_type()

        field_names = [f["name"] for f in model["flds"]]
        fields = {name: note[name] for name in field_names if name in note}

        cards = note.cards()
        deck_name = None
        if cards:
            deck = col.decks.get(cards[0].did)
            if deck:
                deck_name = deck["name"]

        return {
            "id": int(note.id),
            "model_name": model["name"],
            "fields": fields,
            "tags": list(note.tags),
            "deck_name": deck_name,
        }

    return with_collection(collection_path, _do)


def sync_login(collection_path, username, password, endpoint):
    col = Collection(collection_path)
    try:
        auth = col.sync_login(username=username, password=password, endpoint=endpoint)
        return {"hkey": auth.hkey, "endpoint": endpoint}
    finally:
        col.close()


def sync_collection(collection_path, username, password, endpoint):
    col = Collection(collection_path)
    try:
        auth = col.sync_login(username=username, password=password, endpoint=endpoint)
        result = col.sync_collection(auth=auth, sync_media=False)

        required_map = {
            0: "no_changes",
            1: "normal_sync",
            2: "full_sync",
            3: "full_download",
            4: "full_upload",
        }

        return {
            "status": required_map.get(result.required, f"unknown_{result.required}"),
            "server_message": result.server_message if result.server_message else None,
        }
    finally:
        col.close()


def full_upload(collection_path, username, password, endpoint):
    col = Collection(collection_path)
    try:
        auth = col.sync_login(username=username, password=password, endpoint=endpoint)
        col.close_for_full_sync()
        col.full_upload_or_download(auth=auth, server_usn=None, upload=True)
        col.reopen(after_full_sync=True)
        return {"status": "uploaded"}
    finally:
        col.close()


def full_download(collection_path, username, password, endpoint):
    col = Collection(collection_path)
    try:
        auth = col.sync_login(username=username, password=password, endpoint=endpoint)
        col.close_for_full_sync()
        col.full_upload_or_download(auth=auth, server_usn=None, upload=False)
        col.reopen(after_full_sync=True)
        return {"status": "downloaded"}
    finally:
        col.close()
