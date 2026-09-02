package com.tvfull.pro.installer;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;

import java.io.File;
import java.io.FileNotFoundException;

public final class ApkFileProvider extends ContentProvider {
    @Override
    public boolean onCreate() {
        return true;
    }

    @Override
    public String getType(Uri uri) {
        return "application/vnd.android.package-archive";
    }

    @Override
    public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        if (!"r".equals(mode)) {
            throw new FileNotFoundException("Read only");
        }
        File file = resolve(uri);
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY);
    }

    @Override
    public Cursor query(Uri uri, String[] projection, String selection,
                        String[] selectionArgs, String sortOrder) {
        File file;
        try {
            file = resolve(uri);
        } catch (FileNotFoundException e) {
            return null;
        }
        MatrixCursor cursor = new MatrixCursor(new String[]{OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE});
        cursor.addRow(new Object[]{file.getName(), file.length()});
        return cursor;
    }

    private File resolve(Uri uri) throws FileNotFoundException {
        if (getContext() == null) {
            throw new FileNotFoundException("No context");
        }
        String name = uri.getLastPathSegment();
        if (name == null || !name.matches("[A-Za-z0-9._+-]+\\.apk")) {
            throw new FileNotFoundException("Invalid APK path");
        }
        File dir = new File(getContext().getCacheDir(), "downloads");
        File file = new File(dir, name);
        try {
            String dirPath = dir.getCanonicalPath() + File.separator;
            String filePath = file.getCanonicalPath();
            if (!filePath.startsWith(dirPath) || !file.isFile()) {
                throw new FileNotFoundException("APK not found");
            }
        } catch (Exception e) {
            if (e instanceof FileNotFoundException) throw (FileNotFoundException) e;
            throw new FileNotFoundException("Invalid APK path");
        }
        return file;
    }

    @Override public Uri insert(Uri uri, ContentValues values) { throw new UnsupportedOperationException(); }
    @Override public int delete(Uri uri, String selection, String[] selectionArgs) { return 0; }
    @Override public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs) { return 0; }
}
